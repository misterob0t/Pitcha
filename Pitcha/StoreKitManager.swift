import Foundation
import StoreKit

// MARK: - Product IDs

enum PitchaProductID {
    // Consommables — coins
    static let coinsSmall  = "com.adil.pitcha.coins.small"
    static let coinsMedium = "com.adil.pitcha.coins.medium"
    static let coinsLarge  = "com.adil.pitcha.coins.large"
    static let coinsXLarge = "com.adil.pitcha.coins.xlarge"

    // Abonnements Premium
    static let premiumMonthly = "com.adil.pitcha.premium.monthly"
    static let premiumYearly  = "com.adil.pitcha.premium.yearly"

    static let allIDs: Set<String> = [
        coinsSmall, coinsMedium, coinsLarge, coinsXLarge,
        premiumMonthly, premiumYearly
    ]

    /// Nombre de coins accordé pour chaque pack consommable.
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

// MARK: - StoreKitManager

/// Singleton qui charge les produits, gère les achats et écoute
/// les transactions en arrière-plan (renouvellements, restaurations).
/// Utilise StoreKit 2 (async/await, disponible iOS 15+).
@MainActor
final class StoreKitManager: ObservableObject {

    static let shared = StoreKitManager()

    // MARK: - État publié

    /// Produits chargés depuis l'App Store / fichier .storekit local.
    @Published var products: [Product] = []

    /// true si un abonnement Premium est actuellement actif et valide.
    @Published var isPremiumActive: Bool = false

    /// Date d'expiration du Premium actif (nil si aucun abonnement).
    @Published var premiumExpiresAt: Date? = nil

    /// true pendant un appel réseau StoreKit en cours.
    @Published var isLoading: Bool = false

    /// Dernière erreur StoreKit (affichée dans l'UI).
    @Published var errorMessage: String? = nil

    // MARK: - Privé

    private var transactionListenerTask: Task<Void, Error>? = nil

    private init() {
        // Démarrer l'écoute des transactions dès l'init (renouvellements,
        // achats effectués depuis un autre appareil, etc.)
        transactionListenerTask = listenForTransactions()
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Chargement des produits

    /// À appeler au lancement de BoutiqueView.
    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await Product.products(for: PitchaProductID.allIDs)
            // Tri : consommables d'abord, puis abonnements ; par prix croissant
            products = fetched.sorted {
                if $0.type == $1.type { return $0.price < $1.price }
                return $0.type == .consumable
            }
        } catch {
            errorMessage = "Impossible de charger les produits : \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Achat

    /// Lance le paiement Apple et retourne le résultat à traiter.
    /// L'appelant (BoutiqueViewModel) est responsable de créditer Firestore.
    func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            // Mettre à jour le statut Premium si c'est un abonnement
            await updatePremiumStatus()
            await transaction.finish()
            return transaction
        case .userCancelled:
            return nil
        case .pending:
            // Achat en attente (contrôle parental, etc.)
            throw StoreError.pending
        @unknown default:
            return nil
        }
    }

    // MARK: - Restauration

    /// Restaure les achats (abonnements actifs) — obligatoire pour la review Apple.
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

    // MARK: - Vérification du statut Premium

    /// Vérifie toutes les transactions courantes pour déterminer si
    /// un abonnement Premium est actif. Appelé au lancement et après chaque achat.
    func updatePremiumStatus() async {
        var active = false
        var expiresAt: Date? = nil

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == PitchaProductID.premiumMonthly ||
               transaction.productID == PitchaProductID.premiumYearly {
                if transaction.revocationDate == nil {
                    active = true
                    // Prendre la date d'expiration la plus lointaine
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

    /// Écoute les transactions arrivant de l'extérieur (renouvellement automatique,
    /// achat depuis un autre appareil, remboursement, etc.).
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                do {
                    let transaction = try self.checkVerified(result)
                    await self.updatePremiumStatus()
                    await transaction.finish()
                } catch {
                    // Transaction non vérifiable : on ignore silencieusement
                }
            }
        }
    }

    // MARK: - Vérification cryptographique

    /// Vérifie la signature Apple de la transaction.
    /// Lance une erreur si la vérification échoue (transaction falsifiée).
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let value):
            return value
        }
    }

    // MARK: - Helpers produits

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
