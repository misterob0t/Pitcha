import Foundation
import Combine
import RevenueCat

// MARK: - RevenueCatManager
//
// Gère UNIQUEMENT l'abonnement Premium (exigence du Shipaton 2026 : le SDK
// RevenueCat doit réellement servir à au moins un achat). Les coins restent
// sur notre système maison (StoreKit 2 + Cloud Function verifyPurchase) —
// pas besoin de tout migrer, juste ce qui compte pour l'éligibilité.
//
// ⚠️ Remplace REVENUECAT_API_KEY par ta vraie clé publique iOS
// (Project Settings > API Keys sur app.revenuecat.com, commence par "appl_").
enum RevenueCatConfig {
    static let apiKey = "appl_zmkWzFCEGMDXMjyXWMzOtqeXzHI"
    /// Doit correspondre exactement à l'identifiant de l'entitlement créé
    /// dans RevenueCat > Entitlements.
    static let premiumEntitlementId = "premium"
}

@MainActor
final class RevenueCatManager: ObservableObject {
    static let shared = RevenueCatManager()
    private init() {}

    @Published var isPremiumActive = false
    @Published var currentOffering: Offering?
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// À appeler une seule fois au lancement de l'app (PitchaApp.swift).
    static func configure() {
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
    }

    /// À appeler dès qu'on connaît l'utilisateur connecté (après signIn/signUp),
    /// pour que RevenueCat identifie ses achats avec le MÊME identifiant que
    /// Firebase — indispensable pour que le webhook sache quel compte créditer.
    func linkUser(uid: String) async {
        do {
            _ = try await Purchases.shared.logIn(uid)
            await refreshStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// À appeler à la déconnexion.
    func unlinkUser() async {
        _ = try? await Purchases.shared.logOut()
        isPremiumActive = false
    }

    func loadOfferings() async {
        isLoading = true
        do {
            let offerings = try await Purchases.shared.offerings()
            currentOffering = offerings.current
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Retrouve le package RevenueCat correspondant à un identifiant de
    /// produit App Store (ceux déjà utilisés partout ailleurs dans l'app :
    /// PitchaProductID.premiumMonthly / premiumYearly).
    func package(forProductId productId: String) -> Package? {
        currentOffering?.availablePackages.first { $0.storeProduct.productIdentifier == productId }
    }

    /// Achète un package Premium. Le webhook RevenueCat -> Cloud Function
    /// met à jour isPremium/premiumExpiresAt côté serveur ; côté app on
    /// rafraîchit juste l'état local après un court délai pour laisser le
    /// webhook le temps d'arriver (RevenueCat le déclenche quasi instantanément).
    func purchase(package: Package) async throws {
        let result = try await Purchases.shared.purchase(package: package)
        isPremiumActive = result.customerInfo.entitlements[RevenueCatConfig.premiumEntitlementId]?.isActive == true
    }

    func restorePurchases() async throws {
        let info = try await Purchases.shared.restorePurchases()
        isPremiumActive = info.entitlements[RevenueCatConfig.premiumEntitlementId]?.isActive == true
    }

    func refreshStatus() async {
        if let info = try? await Purchases.shared.customerInfo() {
            isPremiumActive = info.entitlements[RevenueCatConfig.premiumEntitlementId]?.isActive == true
        }
    }
}
