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
            sentAt: Date()
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

    /// Recherche un joueur par pseudo exact.
    func findUser(pseudo: String) async throws -> AppUser? {
        let snapshot = try await usersRef
            .whereField("pseudo", isEqualTo: pseudo.trimmingCharacters(in: .whitespaces))
            .limit(to: 1)
            .getDocuments()
        return snapshot.documents.first.flatMap { try? $0.data(as: AppUser.self) }
    }

    func addTeamMember(teamId: String, uid: String) async throws {
        try await teamsRef.document(teamId).updateData([
            "memberIds": FieldValue.arrayUnion([uid])
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
