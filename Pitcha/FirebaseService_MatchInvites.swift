import Foundation
import FirebaseFirestore

// Extension invitations : un ami peut être invité à rejoindre un match
// public directement, sans avoir à le chercher dans la liste. Stocké comme
// une sous-collection sur le document du DESTINATAIRE (une seule invitation
// active par match, grâce à l'ID de document = matchId).
extension FirebaseService {

    func inviteFriendToMatch(matchId: String, matchTitle: String, friendUid: String, fromUid: String, fromPseudo: String) async throws {
        let inviteDoc = usersRef.document(friendUid).collection("matchInvites").document(matchId)
        try await inviteDoc.setData([
            "matchId": matchId,
            "matchTitle": matchTitle,
            "invitedBy": fromUid,
            "invitedByPseudo": fromPseudo,
            "createdAt": Timestamp(date: Date())
        ])
    }

    /// Écoute les invitations reçues. `hasNewInvite` ne passe à true que pour
    /// une VRAIE nouvelle invitation (pas le chargement initial), pour piloter
    /// la notification locale sans spammer à chaque lancement de l'app.
    func listenMatchInvites(uid: String, onChange: @escaping ([MatchInvite], _ hasNewInvite: Bool) -> Void) -> ListenerRegistration {
        usersRef.document(uid).collection("matchInvites")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, _ in
                guard let snapshot else { onChange([], false); return }
                let invites = snapshot.documents.compactMap { try? $0.data(as: MatchInvite.self) }
                let hasNewInvite = !snapshot.metadata.isFromCache
                    && snapshot.documentChanges.contains { $0.type == .added }
                onChange(invites, hasNewInvite)
            }
    }

    /// Accepte : rejoint le match (même règles/coût qu'un join classique),
    /// puis supprime l'invitation.
    func acceptMatchInvite(matchId: String, friendUid: String) async throws {
        try await joinMatch(matchId: matchId, uid: friendUid)
        try await usersRef.document(friendUid).collection("matchInvites").document(matchId).delete()
    }

    func declineMatchInvite(matchId: String, friendUid: String) async throws {
        try await usersRef.document(friendUid).collection("matchInvites").document(matchId).delete()
    }
}
