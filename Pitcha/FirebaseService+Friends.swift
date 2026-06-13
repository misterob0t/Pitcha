import Foundation
import FirebaseFirestore

// Extension amis : relation symétrique (les deux documents sont toujours
// modifiés ensemble via un batch), présence en ligne, équipe avec membres.
extension FirebaseService {

    // MARK: - Amis (relation à double sens)

    /// Envoie une demande d'ami : l'autre doit accepter avant que la
    /// relation existe. La demande atterrit dans SES friendRequests.
    func sendFriendRequest(myUid: String, to friendUid: String) async throws {
        guard myUid != friendUid else { throw FriendsError.cantAddSelf }
        try await usersRef.document(friendUid).updateData([
            "friendRequests": FieldValue.arrayUnion([myUid])
        ])
    }

    /// Accepte une demande : retire la demande + crée la relation des deux
    /// côtés, le tout en un seul batch atomique.
    func acceptFriendRequest(myUid: String, from requesterUid: String) async throws {
        let batch = db.batch()
        batch.updateData(["friendRequests": FieldValue.arrayRemove([requesterUid])],
                         forDocument: usersRef.document(myUid))
        batch.updateData(["friends": FieldValue.arrayUnion([requesterUid])],
                         forDocument: usersRef.document(myUid))
        batch.updateData(["friends": FieldValue.arrayUnion([myUid])],
                         forDocument: usersRef.document(requesterUid))
        try await batch.commit()
    }

    /// Refuse une demande : la retire simplement.
    func declineFriendRequest(myUid: String, from requesterUid: String) async throws {
        try await usersRef.document(myUid).updateData([
            "friendRequests": FieldValue.arrayRemove([requesterUid])
        ])
    }

    /// Supprime l'ami des deux côtés (double arrayRemove, jamais l'un sans l'autre).
    func removeFriend(myUid: String, friendUid: String) async throws {
        let batch = db.batch()
        batch.updateData(["friends": FieldValue.arrayRemove([friendUid])],
                         forDocument: usersRef.document(myUid))
        batch.updateData(["friends": FieldValue.arrayRemove([myUid])],
                         forDocument: usersRef.document(friendUid))
        try await batch.commit()
    }

    /// Écoute en temps réel les profils d'une liste d'uids (statut online inclus).
    /// Firestore limite les requêtes "in" à 10 : on crée 1 listener par paquet.
    func listenUsers(uids: [String], onChange: @escaping ([AppUser]) -> Void) -> [ListenerRegistration] {
        guard !uids.isEmpty else {
            onChange([])
            return []
        }
        let chunks = stride(from: 0, to: uids.count, by: 10).map {
            Array(uids[$0..<min($0 + 10, uids.count)])
        }
        var resultsByChunk: [Int: [AppUser]] = [:]
        let lock = NSLock()

        return chunks.enumerated().map { index, chunk in
            usersRef.whereField(FieldPath.documentID(), in: chunk)
                .addSnapshotListener { snapshot, _ in
                    let users = snapshot?.documents.compactMap { try? $0.data(as: AppUser.self) } ?? []
                    lock.lock()
                    resultsByChunk[index] = users
                    let merged = resultsByChunk.sorted { $0.key < $1.key }.flatMap(\.value)
                    lock.unlock()
                    onChange(merged)
                }
        }
    }

    // MARK: - Présence

    /// Met à jour le "vu en ligne" (appelé périodiquement par SessionViewModel).
    func updatePresence(uid: String) async {
        try? await usersRef.document(uid).updateData([
            "lastSeen": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Équipe avec membres initiaux

    func createTeamWithMembers(name: String, ownerId: String, memberIds: [String], crestIcon: String, crestColorName: String) async throws {
        var allMembers = [ownerId]
        allMembers += memberIds.filter { $0 != ownerId }
        let team = Team(
            name: name,
            ownerId: ownerId,
            memberIds: allMembers,
            createdAt: Date(),
            crestIcon: crestIcon,
            crestColorName: crestColorName
        )
        _ = try teamsRef.addDocument(from: team)
    }
}

enum FriendsError: LocalizedError {
    case cantAddSelf

    var errorDescription: String? {
        switch self {
        case .cantAddSelf: return "Tu ne peux pas t'ajouter toi-même."
        }
    }
}
