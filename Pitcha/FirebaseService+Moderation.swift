import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Signalement & blocage

extension FirebaseService {

    var reportsRef: CollectionReference { db.collection("reports") }

    /// Envoie un signalement. Lecture réservée à la modération (console
    /// Firebase) ; le client ne peut que créer, jamais lire/modifier.
    func reportUser(reportedId: String, reportedPseudo: String, reason: String, context: String, contextId: String? = nil) async throws {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        let report = UserReport(
            reporterId: myUid,
            reportedId: reportedId,
            reportedPseudo: reportedPseudo,
            reason: reason,
            context: context,
            contextId: contextId,
            createdAt: Date()
        )
        _ = try reportsRef.addDocument(from: report)
    }

    /// Bloque ou débloque un utilisateur. Un utilisateur bloqué :
    /// - n'apparaît plus dans la recherche d'amis
    /// - ses messages sont masqués dans les chats partagés
    /// - ne peut plus envoyer de demande d'ami
    func setBlocked(myUid: String, targetUid: String, blocked: Bool) async throws {
        try await usersRef.document(myUid).updateData([
            "blockedUsers": blocked
                ? FieldValue.arrayUnion([targetUid])
                : FieldValue.arrayRemove([targetUid])
        ])
    }
}

// MARK: - Suppression de compte (Guideline 5.1.1)

extension FirebaseService {

    enum AccountDeletionError: LocalizedError {
        case notSignedIn
        var errorDescription: String? {
            "Aucun utilisateur connecté."
        }
    }

    /// Réauthentifie puis supprime intégralement le compte :
    /// document utilisateur, historique de matchs, puis le compte Auth.
    /// Firebase exige une connexion récente pour une suppression de compte
    /// (sécurité) : on réauthentifie avec le mot de passe actuel avant.
    func deleteAccount(password: String) async throws {
        guard let user = Auth.auth().currentUser, let email = user.email else {
            throw AccountDeletionError.notSignedIn
        }

        // 1) Réauthentification obligatoire (sinon Firebase refuse la suppression)
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        try await user.reauthenticate(with: credential)

        let uid = user.uid

        // 2) Supprimer l'historique de matchs (sous-collection)
        let historySnap = try await usersRef.document(uid).collection("history").getDocuments()
        for doc in historySnap.documents {
            try await doc.reference.delete()
        }

        // 3) Supprimer le document utilisateur principal
        try await usersRef.document(uid).delete()

        // 4) Supprimer le compte Firebase Auth (déconnecte automatiquement)
        try await user.delete()
    }
}
