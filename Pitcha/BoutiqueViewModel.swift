import Foundation
import StoreKit
import Combine

// MARK: - Catégories boutique

enum ShopCategory: String, CaseIterable, Identifiable {
    case premium = "Premium"
    case coins   = "Coins"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .premium: return "crown.fill"
        case .coins:   return "circle.circle.fill"
        }
    }
}

// MARK: - Modèles catalogue

struct CosmeticItem: Identifiable {
    let id: String
    let name: String
    let price: Int
    let icon: String
    let colors: [String]
}

struct CoinPack: Identifiable {
    let id: String
    let name: String
    let amount: Int
    let priceLabel: String
}

enum ShopCatalog {
    static let cosmetics: [CosmeticItem] = []

    static let coinPacks: [CoinPack] = [
        CoinPack(id: PitchaProductID.coinsSmall,  name: "Poignée de coins", amount: 50,   priceLabel: "0,99 €"),
        CoinPack(id: PitchaProductID.coinsMedium, name: "Sac de coins",     amount: 150,  priceLabel: "2,49 €"),
        CoinPack(id: PitchaProductID.coinsLarge,  name: "Coffre de coins",  amount: 400,  priceLabel: "4,99 €"),
        CoinPack(id: PitchaProductID.coinsXLarge, name: "Chariot de coins", amount: 1000, priceLabel: "9,99 €")
    ]
}

// MARK: - ViewModel

@MainActor
final class BoutiqueViewModel: ObservableObject {

    @Published var selectedCategory: ShopCategory = .premium
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var isWorking = false
    @Published var purchaseTrigger = false

    private let service  = FirebaseService.shared
    private let storeKit = StoreKitManager.shared

    // MARK: - Chargement initial

    func onAppear() async {
        await storeKit.loadProducts()
        await storeKit.updatePremiumStatus()
    }

    /// Bouton "Réessayer" affiché quand les produits n'ont pas pu être chargés.
    func retryLoadingProducts() async {
        await storeKit.loadProducts()
    }

    // MARK: - Prix affichés (toujours le vrai prix StoreKit, jamais codé en dur)

    func priceLabel(for plan: PremiumPlan) -> String {
        storeKit.product(for: plan.productID)?.displayPrice ?? "..."
    }

    func priceLabel(for pack: CoinPack) -> String {
        storeKit.product(for: pack.id)?.displayPrice ?? "..."
    }

    // MARK: - Abonnement Premium

    func subscribe(plan: PremiumPlan, user: AppUser?) async {
        guard user?.id != nil else { return }
        guard let product = storeKit.product(for: plan.productID) else {
            errorMessage = missingProductMessage()
            return
        }
        isWorking = true
        errorMessage = nil
        successMessage = nil
        do {
            guard let result = try await storeKit.purchase(product) else {
                // Annulé par l'utilisateur
                isWorking = false
                return
            }
            // Le crédit Premium se fait UNIQUEMENT côté serveur, après que
            // la Cloud Function verifyPurchase ait vérifié la signature
            // Apple de cette transaction précise.
            try await service.verifyPurchaseServerSide(jws: result.jws)
            successMessage = "Bienvenue dans Pitcha Premium ! 🎉"
            purchaseTrigger.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    // MARK: - Achat de coins

    func buyCoins(_ pack: CoinPack, user: AppUser?) async {
        guard user?.id != nil else { return }
        guard let product = storeKit.product(for: pack.id) else {
            errorMessage = missingProductMessage()
            return
        }
        isWorking = true
        errorMessage = nil
        successMessage = nil
        do {
            guard let result = try await storeKit.purchase(product) else {
                isWorking = false
                return
            }
            // Idem : le crédit de coins se fait côté serveur uniquement,
            // sur la base de la transaction vérifiée par Apple.
            try await service.verifyPurchaseServerSide(jws: result.jws)
            let amount = PitchaProductID.coinsAmount(for: pack.id)
            successMessage = "+\(amount) coins ajoutés ! 🪙"
            purchaseTrigger.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    /// Message d'erreur précis selon la cause réelle : on ne dit "vérifie
    /// ta connexion" QUE si le chargement a vraiment échoué avec une
    /// erreur réseau. Si le chargement a réussi mais que le produit n'est
    /// simplement pas dans la liste renvoyée par Apple pour ce compte/cette
    /// région, on le dit clairement.
    private func missingProductMessage() -> String {
        if let storeError = storeKit.errorMessage {
            return storeError
        }
        if storeKit.hasAttemptedLoad {
            return "Cet achat n'est pas disponible sur ton compte App Store pour le moment. Vérifie que ton pays/région App Store est bien renseigné dans Réglages > [ton nom] > Média et achats, puis réessaie."
        }
        return "Produit introuvable. Réessaie dans quelques secondes."
    }

    // MARK: - Restauration des achats

    func restorePurchases(user: AppUser?) async {
        guard user?.id != nil else { return }
        isWorking = true
        errorMessage = nil
        successMessage = nil
        await storeKit.restorePurchases()

        if storeKit.isPremiumActive {
            // Re-soumet la transaction active au serveur pour resynchroniser
            // Firestore (utile si le webhook/verifyPurchase initial avait
            // été manqué — nouvel appareil, réinstall, etc.).
            let monthlyJWS = await storeKit.currentEntitlementJWS(for: PitchaProductID.premiumMonthly)
            let yearlyJWS = await storeKit.currentEntitlementJWS(for: PitchaProductID.premiumYearly)
            let jws = monthlyJWS ?? yearlyJWS
            if let jws {
                do {
                    try await service.verifyPurchaseServerSide(jws: jws)
                    successMessage = "Abonnement Premium restauré ✓"
                } catch {
                    errorMessage = error.localizedDescription
                }
            } else {
                successMessage = "Abonnement Premium restauré ✓"
            }
        } else {
            successMessage = "Aucun achat à restaurer."
        }
        purchaseTrigger.toggle()
        isWorking = false
    }
}

// MARK: - Extension PremiumPlan → Product ID StoreKit

extension PremiumPlan {
    var productID: String {
        switch self {
        case .monthly: return PitchaProductID.premiumMonthly
        case .yearly:  return PitchaProductID.premiumYearly
        }
    }
}
