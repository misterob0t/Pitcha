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

    /// Active (ou renouvelle) l'abonnement Premium pour un utilisateur.
    /// Écrit isPremium, premiumExpiresAt, et crédite les coins bonus.
    /// À brancher sur une transaction StoreKit validée côté serveur avant publication.
    func activatePremium(uid: String, plan: PremiumPlan) async throws {
        let userDoc = usersRef.document(uid)

        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let snap = try transaction.getDocument(userDoc)
                guard let user = try? snap.data(as: AppUser.self) else {
                    throw PitchaError.dataCorrupted
                }
                // Si déjà premium actif, on prolonge depuis l'expiration courante
                let baseDate = user.hasPremium ? (user.premiumExpiresAt ?? Date()) : Date()
                let newExpiry = baseDate.addingTimeInterval(plan.duration)

                transaction.updateData([
                    "isPremium": true,
                    "premiumExpiresAt": Timestamp(date: newExpiry),
                    "coins": FieldValue.increment(Int64(plan.bonusCoins))
                ], forDocument: userDoc)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }
}

enum BoutiqueError: LocalizedError {
    case alreadyOwned
    case premiumAlreadyActive

    var errorDescription: String? {
        switch self {
        case .alreadyOwned: return "Tu possèdes déjà cet objet."
        case .premiumAlreadyActive: return "Ton abonnement Premium est déjà actif."
        }
    }
}

// MARK: - Plans d'abonnement Premium

enum PremiumPlan: String, CaseIterable {
    case monthly = "premium_monthly"
    case yearly  = "premium_yearly"

    var duration: TimeInterval {
        switch self {
        case .monthly: return 30 * 24 * 3600
        case .yearly:  return 365 * 24 * 3600
        }
    }

    /// Coins offerts à l'activation (bonus de bienvenue).
    var bonusCoins: Int {
        switch self {
        case .monthly: return 50
        case .yearly:  return 700
        }
    }

    var priceLabel: String {
        switch self {
        case .monthly: return "2,99 €/mois"
        case .yearly:  return "19,99 €/an"
        }
    }

    var displayName: String {
        switch self {
        case .monthly: return "Mensuel"
        case .yearly:  return "Annuel"
        }
    }
}
