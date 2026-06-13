import Foundation
import Combine

// MARK: - Catalogue (local, pas besoin de Firestore pour un catalogue statique)

enum ShopCategory: String, CaseIterable, Identifiable {
    case cosmetics = "Cosmétiques"
    case premium = "Premium"
    case coins = "Coins"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cosmetics: return "paintbrush.fill"
        case .premium: return "crown.fill"
        case .coins: return "circle.circle.fill"
        }
    }
}

struct CosmeticItem: Identifiable {
    let id: String
    let name: String
    let price: Int
    let icon: String
    let colors: [String] // noms de couleurs pour le dégradé
}

struct PremiumPack: Identifiable {
    let id: String
    let name: String
    let price: Int
    let skillPoints: Int
    let tagline: String
}

struct CoinPack: Identifiable {
    let id: String
    let name: String
    let amount: Int
    let priceLabel: String // futur prix StoreKit
}

enum ShopCatalog {
    static let cosmetics: [CosmeticItem] = [
        CosmeticItem(id: "skin_or", name: "Carte Or", price: 100, icon: "sparkles", colors: ["yellow", "orange"]),
        CosmeticItem(id: "skin_neon", name: "Carte Néon", price: 150, icon: "bolt.fill", colors: ["cyan", "purple"]),
        CosmeticItem(id: "skin_carbone", name: "Carte Carbone", price: 200, icon: "hexagon.fill", colors: ["gray", "black"]),
        CosmeticItem(id: "skin_galaxie", name: "Carte Galaxie", price: 300, icon: "moon.stars.fill", colors: ["indigo", "purple"]),
        CosmeticItem(id: "skin_feu", name: "Carte Feu", price: 250, icon: "flame.fill", colors: ["red", "orange"]),
        CosmeticItem(id: "skin_glace", name: "Carte Glace", price: 250, icon: "snowflake", colors: ["cyan", "blue"])
    ]

    static let premiumPacks: [PremiumPack] = [
        PremiumPack(id: "pack_starter", name: "Pack Starter", price: 80, skillPoints: 3, tagline: "Pour bien démarrer"),
        PremiumPack(id: "pack_pro", name: "Pack Pro", price: 200, skillPoints: 10, tagline: "Le choix des compétiteurs"),
        PremiumPack(id: "pack_legende", name: "Pack Légende", price: 450, skillPoints: 25, tagline: "Deviens une légende")
    ]

    static let coinPacks: [CoinPack] = [
        CoinPack(id: "coins_s", name: "Poignée de coins", amount: 50, priceLabel: "0,99 €"),
        CoinPack(id: "coins_m", name: "Sac de coins", amount: 150, priceLabel: "2,49 €"),
        CoinPack(id: "coins_l", name: "Coffre de coins", amount: 400, priceLabel: "4,99 €"),
        CoinPack(id: "coins_xl", name: "Chariot de coins", amount: 1000, priceLabel: "9,99 €")
    ]
}

// MARK: - ViewModel

@MainActor
final class BoutiqueViewModel: ObservableObject {

    @Published var selectedCategory: ShopCategory = .cosmetics
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var isWorking = false
    @Published var purchaseTrigger = false // pour le feedback haptique

    private let service = FirebaseService.shared

    func buyCosmetic(_ item: CosmeticItem, user: AppUser?) async {
        guard let uid = user?.id else { return }
        await run(success: "\(item.name) débloquée !") {
            try await self.service.buyCosmetic(uid: uid, itemId: item.id, price: item.price)
        }
    }

    func buyPack(_ pack: PremiumPack, user: AppUser?) async {
        guard let uid = user?.id else { return }
        await run(success: "+\(pack.skillPoints) points de compétence !") {
            try await self.service.buyPack(uid: uid, price: pack.price, skillPointsGranted: pack.skillPoints)
        }
    }

    /// Placeholder StoreKit : crédite directement les coins.
    /// À remplacer par un vrai achat in-app avant publication.
    func buyCoins(_ pack: CoinPack, user: AppUser?) async {
        guard let uid = user?.id else { return }
        await run(success: "+\(pack.amount) coins !") {
            try await self.service.addCoins(uid: uid, amount: pack.amount)
        }
    }

    private func run(success: String, _ block: @escaping () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        successMessage = nil
        do {
            try await block()
            successMessage = success
            purchaseTrigger.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}
