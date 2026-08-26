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

    // MARK: - Abonnement Premium

    func subscribe(plan: PremiumPlan, user: AppUser?) async {
        guard user?.id != nil else { return }
        guard let product = storeKit.product(for: plan.productID) else {
            errorMessage = "Produit introuvable. Vérifie ta connexion."
            return
        }
        isWorking = true
        errorMessage = nil
        successMessage = nil
        do {
            guard let purchased = try await storeKit.purchase(product) else {
                // Annulé par l'utilisateur
                isWorking = false
                return
            }
            // Le crédit se fait côté serveur, après vérification de la
            // signature Apple — jamais en écrivant directement le compte ici.
            try await service.verifyPurchaseServerSide(jws: purchased.jws)
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
            errorMessage = "Produit introuvable. Vérifie ta connexion."
            return
        }
        isWorking = true
        errorMessage = nil
        successMessage = nil
        do {
            guard let purchased = try await storeKit.purchase(product) else {
                isWorking = false
                return
            }
            // Le montant de coins est déterminé PAR LE SERVEUR à partir du
            // vrai productId de la transaction vérifiée — jamais envoyé
            // depuis le client, pour qu'il ne puisse pas être falsifié.
            try await service.verifyPurchaseServerSide(jws: purchased.jws)
            let amount = PitchaProductID.coinsAmount(for: pack.id)
            successMessage = "+\(amount) coins ajoutés ! 🪙"
            purchaseTrigger.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    // MARK: - Restauration des achats

    func restorePurchases(user: AppUser?) async {
        guard user?.id != nil else { return }
        isWorking = true
        errorMessage = nil
        successMessage = nil
        await storeKit.restorePurchases()
        if storeKit.isPremiumActive {
            do {
                // On renvoie le JWS de l'entitlement actif au serveur — la
                // protection anti-rejeu côté fonction fait que ça ne crédite
                // rien en double si c'était déjà traité, c'est juste une
                // re-confirmation sûre.
                var activeJWS: String? = nil
                for await result in Transaction.currentEntitlements {
                    if let t = try? pitchaCheckVerified(result),
                       (t.productID == PitchaProductID.premiumMonthly ||
                        t.productID == PitchaProductID.premiumYearly) {
                        activeJWS = result.jwsRepresentation
                        break
                    }
                }
                if let jws = activeJWS {
                    try await service.verifyPurchaseServerSide(jws: jws)
                    successMessage = "Abonnement Premium restauré ✓"
                } else {
                    successMessage = "Aucun achat à restaurer."
                }
            } catch {
                errorMessage = error.localizedDescription
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
