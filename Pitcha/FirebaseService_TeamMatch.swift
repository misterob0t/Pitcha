import Foundation
import FirebaseFirestore

// Extension matchs d'équipe : création depuis l'équipe, disponibilité
// (Rejoindre / Indisponible mutuellement exclusifs), messages système.
extension FirebaseService {

    /// Matchs à venir d'une équipe, en temps réel.
    /// Filtre date/statut côté client : un seul whereField = AUCUN index
    /// composite requis, les matchs s'affichent immédiatement.
    func listenTeamMatches(teamId: String, onChange: @escaping ([Match]) -> Void) -> ListenerRegistration {
        matchesRef
            .whereField("teamId", isEqualTo: teamId)
            .addSnapshotListener { snapshot, _ in
                let matches = (snapshot?.documents.compactMap { try? $0.data(as: Match.self) } ?? [])
                    .filter { $0.status == .open && $0.date > Date() }
                    .sorted { $0.date < $1.date }
                onChange(matches)
            }
    }

    /// Crée un match rattaché à une équipe (privé par définition).
    func createTeamMatch(_ match: Match, teamId: String, organizerPseudo: String) async throws {
        _ = try matchesRef.addDocument(from: match)
    }

    /// Déclare la disponibilité d'un joueur pour un match d'équipe.
    /// On retire le joueur des DEUX tableaux, puis on l'ajoute dans le bon —
    /// impossible d'être disponible et indisponible en même temps.
    func setAvailability(matchId: String, teamId: String, user: AppUser, available: Bool) async throws {
        guard let uid = user.id else { return }
        let matchDoc = matchesRef.document(matchId)

        try await matchDoc.updateData([
            "participants": FieldValue.arrayRemove([uid]),
            "unavailable": FieldValue.arrayRemove([uid])
        ])
        try await matchDoc.updateData([
            (available ? "participants" : "unavailable"): FieldValue.arrayUnion([uid])
        ])

    }

    /// L'organisateur annule son match d'équipe (disparaît de la liste,
    /// les listeners filtrent les matchs non-open).
    func cancelTeamMatch(matchId: String, teamId: String, organizerPseudo: String) async throws {
        try await matchesRef.document(matchId).updateData([
            "status": MatchStatus.cancelled.rawValue
        ])
    }

    /// Message système dans le chat d'équipe (rendu centré et grisé).
    func postSystemMessage(teamId: String, text: String) async throws {
        let message = ChatMessage(senderId: "system", senderPseudo: "Système", text: text, sentAt: nil)
        _ = try teamsRef.document(teamId).collection("messages").addDocument(from: message)
    }
}


// MARK: - Messages privés entre amis

extension FirebaseService {

    var dmsRef: CollectionReference { db.collection("dms") }

    /// Identifiant de conversation stable : les deux uids triés.
    func dmChatId(_ a: String, _ b: String) -> String {
        [a, b].sorted().joined(separator: "_")
    }

    func listenDMMessages(chatId: String, onChange: @escaping ([ChatMessage]) -> Void) -> ListenerRegistration {
        dmsRef.document(chatId).collection("messages")
            .order(by: "sentAt")
            .limit(toLast: 100)
            .addSnapshotListener { snapshot, _ in
                let messages = (snapshot?.documents.compactMap { try? $0.data(as: ChatMessage.self) } ?? [])
                    .filter(\.isStillVisible)
                onChange(messages)
            }
    }

    func sendDMMessage(chatId: String, sender: AppUser, text: String) async throws {
        guard let uid = sender.id else { return }
        let expiry = Date().addingTimeInterval(24 * 3600)
        let message = ChatMessage(
            senderId: uid,
            senderPseudo: sender.pseudo,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            sentAt: nil,
            expireAt: expiry,
            naturalExpireAt: expiry
        )
        _ = try dmsRef.document(chatId).collection("messages").addDocument(from: message)
    }
}
