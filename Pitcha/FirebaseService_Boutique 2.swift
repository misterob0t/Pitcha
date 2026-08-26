import Foundation
import FirebaseFirestore
import FirebaseFunctions

// Extension boutique : les cosmétiques/packs internes restent des
// transactions Firestore classiques (pas d'argent réel, juste des coins
// déjà en poche). Coins et Premium, EUX, ne s'obtiennent JAMAIS en écrivant
// directement dans Firestore — uniquement via la Cloud Function
// `verifyPurchase`, qui vérifie la vraie transaction StoreKit signée par
// Apple avant de créditer quoi que ce soit. Voir StoreKitManager.purchase().
extension FirebaseService {

    /// Achète un cosmétique : vérifie le solde, débite, ajoute à ownedItems.
    /// (Paiement en coins déjà possédés — pas un achat App Store, reste OK
    /// en écriture directe puisque ça ne crée pas de valeur, ça la déplace.)
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

    /// Achète un pack premium interne : débite des coins, crédite des skill
    /// points. Même remarque que buyCosmetic — pas de l'argent réel.
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

    /// Envoie la transaction StoreKit signée (JWS) à la Cloud Function
    /// `verifyPurchase`, qui vérifie la signature Apple puis crédite
    /// coins OU Premium selon le VRAI produit contenu dans la transaction
    /// vérifiée — jamais selon ce que le client prétend. Utilisée pour un
    /// achat de coins ET pour un abonnement Premium (même fonction,
    /// le serveur distingue via le productId réel).
    func verifyPurchaseServerSide(jws: String) async throws {
        let functions = Functions.functions(region: "europe-west1")
        do {
            _ = try await functions.httpsCallable("verifyPurchase").call(["signedTransactionInfo": jws])
        } catch {
            throw BoutiqueError.verificationFailed
        }
    }
}

enum BoutiqueError: LocalizedError {
    case alreadyOwned
    case premiumAlreadyActive
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .alreadyOwned: return "Tu possèdes déjà cet objet."
        case .premiumAlreadyActive: return "Ton abonnement Premium est déjà actif."
        case .verificationFailed: return "La vérification de l'achat a échoué côté serveur. Contacte le support si le paiement a bien été prélevé."
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
