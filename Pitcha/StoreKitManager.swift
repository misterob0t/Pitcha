import Foundation
import StoreKit
import Combine

// MARK: - Product IDs

enum PitchaProductID {
    static let coinsSmall  = "com.adil.pitcha.coins.small"
    static let coinsMedium = "com.adil.pitcha.coins.medium"
    static let coinsLarge  = "com.adil.pitcha.coins.large"
    static let coinsXLarge = "com.adil.pitcha.coins.xlarge"

    static let premiumMonthly = "com.adil.pitcha.premium.monthly"
    static let premiumYearly  = "com.adil.pitcha.premium.yearly"

    static let allIDs: Set<String> = [
        coinsSmall, coinsMedium, coinsLarge, coinsXLarge,
        premiumMonthly, premiumYearly
    ]

    static func coinsAmount(for productID: String) -> Int {
        switch productID {
        case coinsSmall:  return 50
        case coinsMedium: return 150
        case coinsLarge:  return 400
        case coinsXLarge: return 1000
        default:          return 0
        }
    }
}

// MARK: - Vérification cryptographique (fonction libre, sans isolation d'acteur)

func pitchaCheckVerified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .unverified:
        throw StoreError.failedVerification
    case .verified(let value):
        return value
    }
}

// MARK: - StoreKitManager

@MainActor
final class StoreKitManager: ObservableObject {

    static let shared = StoreKitManager()

    @Published var products: [Product] = []
    @Published var isPremiumActive: Bool = false
    @Published var premiumExpiresAt: Date? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    /// true dès qu'on a tenté au moins un chargement (réussi ou non) —
    /// permet de distinguer "encore en train de charger" de "chargé mais
    /// vide" côté UI.
    @Published var hasAttemptedLoad = false

    /// true si loadProducts() s'est terminé SANS erreur mais que le store
    /// a renvoyé moins de produits que prévu (config App Store Connect,
    /// pas un souci réseau de l'utilisateur).
    @Published var productsPartiallyUnavailable = false

    private var transactionListenerTask: Task<Void, Error>? = nil

    private init() {
        transactionListenerTask = listenForTransactions()
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Chargement des produits

    /// Charge les produits avec 2 tentatives (backoff court) : certains
    /// réseaux (roaming, VPN, Wi-Fi capricieux à l'étranger) font échouer
    /// le premier appel StoreKit alors que le second passe.
    func loadProducts(retries: Int = 2) async {
        isLoading = true
        errorMessage = nil

        for attempt in 0...retries {
            do {
                let fetched = try await Product.products(for: PitchaProductID.allIDs)
                products = fetched.sorted {
                    if $0.type == $1.type { return $0.price < $1.price }
                    return $0.type == .consumable
                }
                productsPartiallyUnavailable = fetched.count < PitchaProductID.allIDs.count
                errorMessage = nil
                isLoading = false
                hasAttemptedLoad = true
                return
            } catch {
                if attempt == retries {
                    errorMessage = "Impossible de charger les produits : \(error.localizedDescription)"
                } else {
                    try? await Task.sleep(for: .seconds(1.5))
                }
            }
        }
        isLoading = false
        hasAttemptedLoad = true
    }

    // MARK: - Achat

    /// Retourne la transaction ET sa représentation JWS signée par Apple —
    /// c'est cette dernière qu'il faut envoyer à la Cloud Function
    /// `verifyPurchase` (voir FirebaseService.verifyPurchaseServerSide).
    /// nil si l'utilisateur a annulé.
    func purchase(_ product: Product) async throws -> (transaction: Transaction, jws: String)? {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let jws = verification.jwsRepresentation
            let transaction = try pitchaCheckVerified(verification)
            await updatePremiumStatus()
            await transaction.finish()
            return (transaction, jws)
        case .userCancelled:
            return nil
        case .pending:
            throw StoreError.pending
        @unknown default:
            return nil
        }
    }

    // MARK: - Restauration

    func restorePurchases() async {
        isLoading = true
        do {
            try await AppStore.sync()
            await updatePremiumStatus()
        } catch {
            errorMessage = "Restauration impossible : \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// JWS de la transaction actuellement active pour un produit donné
    /// (utilisé après restorePurchases() pour re-soumettre au serveur).
    func currentEntitlementJWS(for productID: String) async -> String? {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == productID {
                return result.jwsRepresentation
            }
        }
        return nil
    }

    // MARK: - Statut Premium

    func updatePremiumStatus() async {
        var active = false
        var expiresAt: Date? = nil

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? pitchaCheckVerified(result) else { continue }
            if transaction.productID == PitchaProductID.premiumMonthly ||
               transaction.productID == PitchaProductID.premiumYearly {
                if transaction.revocationDate == nil {
                    active = true
                    if let exp = transaction.expirationDate {
                        expiresAt = expiresAt.map { max($0, exp) } ?? exp
                    }
                }
            }
        }

        isPremiumActive = active
        premiumExpiresAt = expiresAt
    }

    // MARK: - Écoute continue des transactions

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached(priority: .background) {
            for await result in Transaction.updates {
                // pitchaCheckVerified est une fonction libre : zéro isolation d'acteur
                if let transaction = try? pitchaCheckVerified(result) {
                    await StoreKitManager.shared.updatePremiumStatus()
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Helpers

    var coinProducts: [Product] {
        products.filter { $0.type == .consumable }
    }

    var subscriptionProducts: [Product] {
        products.filter { $0.type == .autoRenewable }
    }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }
}

// MARK: - Erreurs StoreKit

enum StoreError: LocalizedError {
    case failedVerification
    case pending

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "La vérification de l'achat a échoué. Contacte le support."
        case .pending:
            return "Achat en attente d'approbation (contrôle parental activé)."
        }
    }
}
