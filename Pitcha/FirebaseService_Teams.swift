import Foundation
import FirebaseFirestore

// Extension équipes : chat, membres, recherche de joueurs.
// FirebaseService.swift reste inchangé.
extension FirebaseService {

    // MARK: - Chat d'équipe (sous-collection teams/{id}/messages)

    func listenTeamMessages(teamId: String, onChange: @escaping ([ChatMessage]) -> Void) -> ListenerRegistration {
        teamsRef.document(teamId).collection("messages")
            .order(by: "sentAt")
            .limit(toLast: 100)
            .addSnapshotListener { snapshot, _ in
                let messages = snapshot?.documents.compactMap { try? $0.data(as: ChatMessage.self) } ?? []
                onChange(messages)
            }
    }

    func sendTeamMessage(teamId: String, sender: AppUser, text: String) async throws {
        guard let uid = sender.id else { return }
        let message = ChatMessage(
            senderId: uid,
            senderPseudo: sender.pseudo,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            sentAt: nil
        )
        _ = try teamsRef.document(teamId).collection("messages").addDocument(from: message)
    }

    // MARK: - Membres

    /// Récupère les profils des membres (requêtes "in" par paquets de 10, limite Firestore).
    func fetchUsers(uids: [String]) async throws -> [AppUser] {
        guard !uids.isEmpty else { return [] }
        var result: [AppUser] = []
        let chunks = stride(from: 0, to: uids.count, by: 10).map {
            Array(uids[$0..<min($0 + 10, uids.count)])
        }
        for chunk in chunks {
            let snapshot = try await usersRef
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            result += snapshot.documents.compactMap { try? $0.data(as: AppUser.self) }
        }
        return result
    }

    /// Recherche un joueur par pseudo, insensible à la casse.
    /// Ne dépend d'AUCUN champ pré-calculé (pseudoLower) : on récupère tous
    /// les utilisateurs et on compare en mémoire. Fonctionne immédiatement
    /// pour tous les comptes, peu importe quand ils ont été créés ou s'ils
    /// se sont reconnectés depuis. Le coût est négligeable tant que la base
    /// reste sous quelques milliers d'utilisateurs.
    func findUser(pseudo: String) async throws -> AppUser? {
        let target = pseudo.trimmingCharacters(in: .whitespaces).lowercased()
        guard !target.isEmpty else { return nil }

        // 1) Essai rapide sur pseudoLower (gratuit si le champ existe)
        let snap = try await usersRef
            .whereField("pseudoLower", isEqualTo: target)
            .limit(to: 1)
            .getDocuments()
        if let doc = snap.documents.first,
           let user = try? doc.data(as: AppUser.self) {
            return user
        }

        // 2) Fallback : scan borné, comparaison en mémoire.
        // ⚠️ Coût Firestore : chaque recherche infructueuse sur pseudoLower
        // déclenche jusqu'à 300 lectures payantes. Le backfill automatique
        // au login (voir SessionViewModel.attachUserListener) réduit ce cas
        // au fil du temps — quasiment tous les comptes actifs auront
        // pseudoLower renseigné après quelques semaines, et ce fallback ne
        // se déclenchera plus que pour des comptes jamais reconnectés.
        let all = try await usersRef.limit(to: 300).getDocuments()
        for doc in all.documents {
            if let user = try? doc.data(as: AppUser.self),
               user.pseudo.trimmingCharacters(in: .whitespaces).lowercased() == target {
                return user
            }
        }
        return nil
    }

    func addTeamMember(teamId: String, uid: String) async throws {
        try await teamsRef.document(teamId).updateData([
            "memberIds": FieldValue.arrayUnion([uid])
        ])
        try await usersRef.document(uid).updateData([
            "teamsJoinedCount": FieldValue.increment(Int64(1))
        ])
    }

    func removeTeamMember(teamId: String, uid: String) async throws {
        try await teamsRef.document(teamId).updateData([
            "memberIds": FieldValue.arrayRemove([uid])
        ])
    }

    func deleteTeam(teamId: String) async throws {
        try await teamsRef.document(teamId).delete()
    }
}


extension FirebaseService {
    /// Renseigne pseudoLower si absent (comptes créés avant l'ajout du champ).
    func backfillPseudoLowerIfNeeded(uid: String) async {
        guard let snap = try? await usersRef.document(uid).getDocument(),
              let user = try? snap.data(as: AppUser.self),
              user.pseudoLower == nil else { return }
        try? await usersRef.document(uid).updateData([
            "pseudoLower": user.pseudo.trimmingCharacters(in: .whitespaces).lowercased()
        ])
    }
}
