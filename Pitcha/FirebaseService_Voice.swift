import Foundation
import FirebaseStorage
import FirebaseFirestore

// MARK: - Messages vocaux et photos — upload + envoi (DM, équipe, club)
//
// Un seul point d'upload par type de média, puis des petites fonctions
// d'envoi qui réutilisent chacune la collection "messages" déjà en place
// pour son contexte — même modèle ChatMessage partout, juste le champ
// média rempli (voiceURL ou photoURL) à la place de text.

extension FirebaseService {

    private var storage: Storage { Storage.storage() }

    /// Durée de vie par défaut d'un message avant qu'il ne disparaisse de
    /// l'affichage (sauf s'il est explicitement gardé) — appliquée à
    /// l'envoi, aussi bien pour le texte que le vocal ou la photo.
    private static var defaultMessageExpiry: Date {
        Date().addingTimeInterval(24 * 3600)
    }

    /// Upload un vocal enregistré localement et retourne son URL publique.
    /// Chemin séparé par contexte pour rester lisible dans la Console Storage.
    private func uploadVoiceMessage(fileURL: URL, context: String, contextId: String) async throws -> String {
        let filename = "\(UUID().uuidString).m4a"
        let ref = storage.reference().child("voice_messages/\(context)/\(contextId)/\(filename)")
        let metadata = StorageMetadata()
        metadata.contentType = "audio/m4a"

        let data = try Data(contentsOf: fileURL)
        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()

        // Fichier temporaire local — plus besoin une fois uploadé.
        try? FileManager.default.removeItem(at: fileURL)

        return url.absoluteString
    }

    /// Upload une photo (déjà compressée en JPEG par l'appelant) et
    /// retourne son URL publique.
    private func uploadChatPhoto(data: Data, context: String, contextId: String) async throws -> String {
        let filename = "\(UUID().uuidString).jpg"
        let ref = storage.reference().child("chat_photos/\(context)/\(contextId)/\(filename)")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

    // MARK: - Message privé

    func sendVoiceDMMessage(chatId: String, sender: AppUser, fileURL: URL, duration: TimeInterval) async throws {
        guard let uid = sender.id else { return }
        let voiceURL = try await uploadVoiceMessage(fileURL: fileURL, context: "dm", contextId: chatId)
        let expiry = Self.defaultMessageExpiry
        let message = ChatMessage(
            senderId: uid, senderPseudo: sender.pseudo, text: "",
            voiceURL: voiceURL, voiceDuration: duration, sentAt: nil,
            expireAt: expiry, naturalExpireAt: expiry
        )
        _ = try dmsRef.document(chatId).collection("messages").addDocument(from: message)
    }

    func sendPhotoDMMessage(chatId: String, sender: AppUser, photoData: Data) async throws {
        guard let uid = sender.id else { return }
        let photoURL = try await uploadChatPhoto(data: photoData, context: "dm", contextId: chatId)
        let expiry = Self.defaultMessageExpiry
        let message = ChatMessage(
            senderId: uid, senderPseudo: sender.pseudo, text: "",
            photoURL: photoURL, sentAt: nil,
            expireAt: expiry, naturalExpireAt: expiry
        )
        _ = try dmsRef.document(chatId).collection("messages").addDocument(from: message)
    }

    // MARK: - Chat d'équipe

    func sendVoiceTeamMessage(teamId: String, sender: AppUser, fileURL: URL, duration: TimeInterval) async throws {
        guard let uid = sender.id else { return }
        let voiceURL = try await uploadVoiceMessage(fileURL: fileURL, context: "team", contextId: teamId)
        let expiry = Self.defaultMessageExpiry
        let message = ChatMessage(
            senderId: uid, senderPseudo: sender.pseudo, text: "",
            voiceURL: voiceURL, voiceDuration: duration, sentAt: nil,
            expireAt: expiry, naturalExpireAt: expiry
        )
        _ = try teamsRef.document(teamId).collection("messages").addDocument(from: message)
    }

    func sendPhotoTeamMessage(teamId: String, sender: AppUser, photoData: Data) async throws {
        guard let uid = sender.id else { return }
        let photoURL = try await uploadChatPhoto(data: photoData, context: "team", contextId: teamId)
        let expiry = Self.defaultMessageExpiry
        let message = ChatMessage(
            senderId: uid, senderPseudo: sender.pseudo, text: "",
            photoURL: photoURL, sentAt: nil,
            expireAt: expiry, naturalExpireAt: expiry
        )
        _ = try teamsRef.document(teamId).collection("messages").addDocument(from: message)
    }

    // MARK: - Chat de club

    func sendVoiceClubMessage(clubId: String, sender: AppUser, fileURL: URL, duration: TimeInterval) async throws {
        guard let uid = sender.id else { return }
        let voiceURL = try await uploadVoiceMessage(fileURL: fileURL, context: "club", contextId: clubId)
        let expiry = Self.defaultMessageExpiry
        let message = ChatMessage(
            senderId: uid, senderPseudo: sender.pseudo, text: "",
            voiceURL: voiceURL, voiceDuration: duration, sentAt: nil,
            expireAt: expiry, naturalExpireAt: expiry
        )
        _ = try clubsRef.document(clubId).collection("messages").addDocument(from: message)
    }

    func sendPhotoClubMessage(clubId: String, sender: AppUser, photoData: Data) async throws {
        guard let uid = sender.id else { return }
        let photoURL = try await uploadChatPhoto(data: photoData, context: "club", contextId: clubId)
        let expiry = Self.defaultMessageExpiry
        let message = ChatMessage(
            senderId: uid, senderPseudo: sender.pseudo, text: "",
            photoURL: photoURL, sentAt: nil,
            expireAt: expiry, naturalExpireAt: expiry
        )
        _ = try clubsRef.document(clubId).collection("messages").addDocument(from: message)
    }

    // MARK: - Garder / retirer la protection d'un message (bascule dans les 2 sens)

    /// `currentlyKept` et `naturalExpireAt` viennent de l'objet déjà en
    /// mémoire côté app (le listener temps réel) — pas besoin de relire le
    /// document avant d'écrire.
    ///
    /// Garder : retire `expireAt` complètement — c'est la seule façon de
    /// vraiment échapper à la suppression automatique (TTL), qui ne
    /// regarde que ce champ, jamais `kept`.
    ///
    /// Retirer la protection : restaure `expireAt` à sa valeur D'ORIGINE
    /// (`naturalExpireAt`, jamais modifiée depuis l'envoi) — pas un
    /// nouveau délai de 24h à partir de maintenant. Si cette date
    /// d'origine est déjà passée, le message redisparaît donc
    /// immédiatement : la protection ne lui a pas donné un sursis
    /// supplémentaire, juste suspendu temporairement son expiration.
    func toggleKeepMessage(context: String, contextId: String, messageId: String, currentlyKept: Bool, naturalExpireAt: Date?) async {
        let ref: DocumentReference
        switch context {
        case "dm":   ref = dmsRef.document(contextId).collection("messages").document(messageId)
        case "team": ref = teamsRef.document(contextId).collection("messages").document(messageId)
        case "club": ref = clubsRef.document(contextId).collection("messages").document(messageId)
        default: return
        }

        if currentlyKept {
            try? await ref.updateData([
                "kept": false,
                "expireAt": naturalExpireAt ?? Date()
            ])
        } else {
            try? await ref.updateData([
                "kept": true,
                "expireAt": FieldValue.delete()
            ])
        }
    }

    // MARK: - Marquer une conversation comme lue (remise à 0 de SON PROPRE compteur)

    func markDMRead(chatId: String, uid: String) async {
        try? await dmsRef.document(chatId).setData([
            "unreadCounts": [uid: 0],
            "lastReadAt": [uid: FieldValue.serverTimestamp()]
        ], merge: true)
    }

    /// Lecture ponctuelle (pas un listener) — appelée une fois par ligne
    /// ami dans la liste, cohérent avec le reste de l'app qui évite les
    /// listeners multipliés par le nombre d'éléments d'une liste.
    func fetchDMUnreadCount(myUid: String, friendUid: String) async -> Int {
        let chatId = dmChatId(myUid, friendUid)
        guard let snap = try? await dmsRef.document(chatId).getDocument() else { return 0 }
        let counts = snap.data()?["unreadCounts"] as? [String: Int]
        return counts?[myUid] ?? 0
    }

    func markTeamMessagesRead(teamId: String, uid: String) async {
        try? await teamsRef.document(teamId).updateData([
            "unreadCounts.\(uid)": 0,
            "lastReadAt.\(uid)": FieldValue.serverTimestamp()
        ])
    }

    func markClubMessagesRead(clubId: String, uid: String) async {
        try? await clubsRef.document(clubId).updateData([
            "unreadCounts.\(uid)": 0,
            "lastReadAt.\(uid)": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Qui a vu ce message (appui long sur une bulle)

    /// Compare la date d'envoi du message à la dernière date de lecture de
    /// chaque membre — quiconque a ouvert la conversation APRÈS l'envoi
    /// l'a forcément vu, sans avoir besoin d'un accusé de lecture stocké
    /// par message individuellement.
    func fetchSeenBy(context: String, contextId: String, messageSentAt: Date, excludingUid: String) async -> [String] {
        var lastReadAt: [String: Any] = [:]
        var candidateUids: [String] = []

        switch context {
        case "team":
            guard let snap = try? await teamsRef.document(contextId).getDocument(),
                  let team = try? snap.data(as: Team.self) else { return [] }
            lastReadAt = snap.data()?["lastReadAt"] as? [String: Any] ?? [:]
            candidateUids = team.memberIds
        case "club":
            guard let snap = try? await clubsRef.document(contextId).getDocument(),
                  let club = try? snap.data(as: Club.self) else { return [] }
            lastReadAt = snap.data()?["lastReadAt"] as? [String: Any] ?? [:]
            candidateUids = club.starterIds + club.substituteIds
        case "dm":
            guard let snap = try? await dmsRef.document(contextId).getDocument() else { return [] }
            lastReadAt = snap.data()?["lastReadAt"] as? [String: Any] ?? [:]
            candidateUids = contextId.split(separator: "_").map(String.init)
        default:
            return []
        }

        let seenUids = candidateUids.filter { uid in
            guard uid != excludingUid, let ts = lastReadAt[uid] as? Timestamp else { return false }
            return ts.dateValue() >= messageSentAt
        }
        guard !seenUids.isEmpty else { return [] }
        let users = (try? await fetchUsers(uids: seenUids)) ?? []
        return users.map(\.pseudo)
    }

    // MARK: - Total de non-lus (badge app + pastille onglet Équipes)

    /// Additionne les non-lus sur toutes les équipes, tous les clubs, et
    /// toutes les conversations privées de l'utilisateur. Fait en petits
    /// lots parallèles plutôt qu'un par un — reste rapide même avec
    /// plusieurs dizaines d'amis/équipes.
    func computeTotalUnreadCount(uid: String, teamIds: [String], clubIds: [String], friendIds: [String]) async -> Int {
        async let teamsTotal = withTaskGroup(of: Int.self) { group -> Int in
            for teamId in teamIds {
                group.addTask {
                    guard let snap = try? await self.teamsRef.document(teamId).getDocument(),
                          let team = try? snap.data(as: Team.self) else { return 0 }
                    return team.unreadCount(for: uid)
                }
            }
            var sum = 0
            for await value in group { sum += value }
            return sum
        }

        async let clubsTotal = withTaskGroup(of: Int.self) { group -> Int in
            for clubId in clubIds {
                group.addTask {
                    guard let snap = try? await self.clubsRef.document(clubId).getDocument(),
                          let club = try? snap.data(as: Club.self) else { return 0 }
                    return club.unreadCount(for: uid)
                }
            }
            var sum = 0
            for await value in group { sum += value }
            return sum
        }

        async let dmsTotal = withTaskGroup(of: Int.self) { group -> Int in
            for friendId in friendIds {
                let chatId = dmChatId(uid, friendId)
                group.addTask {
                    guard let snap = try? await self.dmsRef.document(chatId).getDocument() else { return 0 }
                    let counts = snap.data()?["unreadCounts"] as? [String: Int]
                    return counts?[uid] ?? 0
                }
            }
            var sum = 0
            for await value in group { sum += value }
            return sum
        }

        return await teamsTotal + (await clubsTotal) + (await dmsTotal)
    }

    // MARK: - Suppression (auto uniquement — vérifié aussi côté règles Firestore)

    /// Supprime un message dans son contexte (dm/team/club). Si c'était un
    /// vocal ou une photo, supprime aussi le fichier associé dans Storage —
    /// sinon il resterait orphelin et continuerait à occuper de l'espace
    /// payant.
    func deleteMessage(context: String, contextId: String, messageId: String, voiceURL: String?, photoURL: String? = nil) async throws {
        let collectionRef: CollectionReference
        switch context {
        case "dm":   collectionRef = dmsRef.document(contextId).collection("messages")
        case "team": collectionRef = teamsRef.document(contextId).collection("messages")
        case "club": collectionRef = clubsRef.document(contextId).collection("messages")
        default: return
        }

        try await collectionRef.document(messageId).delete()

        if let voiceURL, let url = URL(string: voiceURL) {
            try? await storage.reference(forURL: url.absoluteString).delete()
        }
        if let photoURL, let url = URL(string: photoURL) {
            try? await storage.reference(forURL: url.absoluteString).delete()
        }
    }
}
