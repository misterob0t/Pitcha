import Foundation
import FirebaseFirestore

// Extension boutique : tous les achats sont des transactions atomiques
// (vérification du solde + débit + attribution dans la même opération).
extension FirebaseService {

    /// Achète un cosmétique : vérifie le solde, débite, ajoute à ownedItems.
    func buyCosmetic(uid: String, itemId: String, price: Int) async throws {
        let userDoc = usersRef.document(uid)

        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let snap = try transaction.getDocument(userDoc)
                guard let user = try? snap.data(as: AppUser.self) else {
                    throw PitchaError.dataCorrupted
                }
                guard !user.owned.contains(itemId) else { throw BoutiqueError.alreadyOwned }
                guard user.coins >= price else { throw PitchaError.notEnoughCoins }

                transaction.updateData([
                    "coins": FieldValue.increment(Int64(-price)),
                    "ownedItems": FieldValue.arrayUnion([itemId])
                ], forDocument: userDoc)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    /// Achète un pack premium : débite des coins, crédite des skill points.
    func buyPack(uid: String, price: Int, skillPointsGranted: Int) async throws {
        let userDoc = usersRef.document(uid)

        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let snap = try transaction.getDocument(userDoc)
                guard let user = try? snap.data(as: AppUser.self) else {
                    throw PitchaError.dataCorrupted
                }
                guard user.coins >= price else { throw PitchaError.notEnoughCoins }

                transaction.updateData([
                    "coins": FieldValue.increment(Int64(-price)),
                    "skillPoints": FieldValue.increment(Int64(skillPointsGranted))
                ], forDocument: userDoc)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    /// Crédite des coins. Placeholder en attendant l'intégration StoreKit
    /// (achats in-app réels) — à brancher sur les transactions App Store.
    func addCoins(uid: String, amount: Int) async throws {
        try await usersRef.document(uid).updateData([
            "coins": FieldValue.increment(Int64(amount))
        ])
    }
}

enum BoutiqueError: LocalizedError {
    case alreadyOwned

    var errorDescription: String? {
        switch self {
        case .alreadyOwned: return "Tu possèdes déjà cet objet."
        }
    }
}
