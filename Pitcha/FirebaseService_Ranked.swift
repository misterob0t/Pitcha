import Foundation
import FirebaseFirestore

// Extension Classé : la distribution de PL/XP est désormais gérée côté
// serveur (Cloud Functions, voir matchFinalization.js) — plus aucune
// écriture de rankedPL/xp/division n'est autorisée depuis le client.
// Ce fichier ne garde que les votes de fiabilité, qui restent légers et
// protégés par une garde anti-double-vote côté client.
extension FirebaseService {

    /// Enregistre les notes de fiabilité données par un participant aux
    /// autres joueurs d'un match. Une seule soumission par (match, votant) :
    /// le document voteDoc sert à la fois de trace ET de garde contre le
    /// double-comptage (vérifié dans la transaction avant tout incrément).
    func submitReliabilityVotes(matchId: String, voterId: String, ratings: [String: Int]) async throws {
        let voteDoc = matchesRef.document(matchId).collection("reliabilityVotes").document(voterId)

        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let existing = try transaction.getDocument(voteDoc)
                guard !existing.exists else {
                    throw PitchaError.alreadyVoted
                }

                for (ratedUid, rating) in ratings {
                    let clamped = max(1, min(5, rating))
                    let ratedUserDoc = self.usersRef.document(ratedUid)
                    transaction.updateData([
                        "reliabilitySum": FieldValue.increment(Int64(clamped)),
                        "reliabilityCount": FieldValue.increment(Int64(1))
                    ], forDocument: ratedUserDoc)
                }

                transaction.setData([
                    "ratings": ratings,
                    "submittedAt": Timestamp(date: Date())
                ], forDocument: voteDoc)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    /// Vérifie si l'utilisateur a déjà voté la fiabilité pour ce match
    /// (pour ne pas réafficher la sheet de vote si déjà fait).
    func hasSubmittedReliabilityVotes(matchId: String, voterId: String) async -> Bool {
        let doc = matchesRef.document(matchId).collection("reliabilityVotes").document(voterId)
        return (try? await doc.getDocument().exists) ?? false
    }
}
