import Foundation
import FirebaseFirestore
import FirebaseFunctions

// Extension Classé : la distribution de PL/XP est désormais gérée côté
// serveur (Cloud Functions, voir matchFinalization.js) — plus aucune
// écriture de rankedPL/xp/division n'est autorisée depuis le client.
// Ce fichier ne garde que la notation de fiabilité, qui passe elle aussi
// par une Cloud Function (touche les comptes d'AUTRES joueurs).
extension FirebaseService {

    /// Note la fiabilité d'UN participant précis (en tapant sa bulle sur la
    /// feuille de match) — pas un vote groupé pour tout le monde d'un coup.
    /// Vérifié côté serveur (participant du match, match terminé, pas de
    /// double vote sur CE joueur précis) plutôt que confié au client.
    func rateParticipantReliability(matchId: String, targetUid: String, rating: Int) async throws {
        let functions = Functions.functions(region: "europe-west1")
        _ = try await functions.httpsCallable("rateParticipantReliability").call([
            "matchId": matchId,
            "targetUid": targetUid,
            "rating": rating
        ])
    }

    /// Vérifie si l'utilisateur a déjà noté CE participant précis pour ce
    /// match (pour désactiver/masquer le bouton une fois fait).
    func hasRatedParticipant(matchId: String, voterId: String, targetUid: String) async -> Bool {
        let doc = matchesRef.document(matchId).collection("reliabilityVotes").document(voterId)
        guard let snap = try? await doc.getDocument(), snap.exists,
              let ratedUids = snap.data()?["ratedUids"] as? [String] else { return false }
        return ratedUids.contains(targetUid)
    }
}
