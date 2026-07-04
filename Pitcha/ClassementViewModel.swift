import Foundation
import Combine
import SwiftUI

enum RankScope: String, CaseIterable, Identifiable {
    case regional = "Régional"
    case national = "National"
    case mondial  = "Mondial"
    var id: String { rawValue }
}

@MainActor
final class ClassementViewModel: ObservableObject {
    @Published var scope: RankScope = .regional
    @Published var players: [AppUser] = []
    @Published var myRank: Int?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = FirebaseService.shared

    func load(user: AppUser?) async {
        isLoading = players.isEmpty
        errorMessage = nil
        do {
            switch scope {
            case .regional:
                // Classement filtré à la ville de l'utilisateur — jamais
                // mélangé avec les autres villes. Si l'utilisateur n'a pas
                // encore de ville renseignée (ancien compte créé avant
                // l'ajout de ce champ), on retombe sur Paris par défaut
                // plutôt que de planter.
                let city = user?.city ?? "Paris"
                players = try await service.fetchRegionalLeaderboard(city: city)
                if let user {
                    if let index = players.firstIndex(where: { $0.id == user.id }) {
                        myRank = index + 1
                    } else {
                        myRank = try await service.fetchRegionalRankByGoals(city: city, goals: user.totalGoals)
                    }
                }
            case .national, .mondial:
                // 1 lecture au lieu de 50+ : on tente d'abord le classement
                // précalculé par la Cloud Function planifiée.
                if let precomputed = try await service.fetchPrecomputedLeaderboard() {
                    players = precomputed
                } else {
                    // Repli : calcul live (coûteux), seulement si le précalculé
                    // est absent ou trop vieux.
                    let fetched = try await service.fetchLeaderboard(limit: 50)
                    players = fetched.sorted { ($0.totalGoals, $0.xp) > ($1.totalGoals, $1.xp) }
                }
                if let user {
                    if let index = players.firstIndex(where: { $0.id == user.id }) {
                        myRank = index + 1
                    } else {
                        myRank = try await service.fetchRankByGoals(goals: user.totalGoals)
                    }
                }
            }
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    func isMe(_ player: AppUser, user: AppUser?) -> Bool {
        player.id != nil && player.id == user?.id
    }

    func isOutsideTop(user: AppUser?) -> Bool {
        guard let uid = user?.id else { return false }
        return !players.contains { $0.id == uid }
    }
}

// MARK: - Rareté des badges

enum BadgeRarity: Int, CaseIterable {
    case common    = 0   // Commun    — gris
    case rare      = 1   // Rare      — bleu
    case epic      = 2   // Épique    — violet
    case legendary = 3   // Légendaire — or

    var label: String {
        switch self {
        case .common:    return "Commun"
        case .rare:      return "Rare"
        case .epic:      return "Épique"
        case .legendary: return "Légendaire"
        }
    }

    /// Couleurs de fond selon la rareté
    var colors: [Color] {
        switch self {
        case .common:    return [Color(white: 0.55), Color(white: 0.38)]
        case .rare:      return [Color(hex: "3B82F6"), Color(hex: "1D4ED8")]
        case .epic:      return [Color(hex: "A855F7"), Color(hex: "6D28D9")]
        case .legendary: return [Color(hex: "F59E0B"), Color(hex: "B45309")]
        }
    }

    /// Couleur de texte du label
    var textColor: Color {
        switch self {
        case .common:    return Color(white: 0.55)
        case .rare:      return Color(hex: "3B82F6")
        case .epic:      return Color(hex: "A855F7")
        case .legendary: return Color(hex: "F59E0B")
        }
    }
}

// MARK: - Badge

struct PlayerBadge: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String          // SF Symbol icône centrale
    let shape: String         // SF Symbol de fond
    let rarity: BadgeRarity
    let target: Int
    let progress: Int

    var isUnlocked: Bool     { progress >= target }
    var clampedProgress: Int { min(progress, target) }

    /// Gradient selon la rareté (verrouillé = gris)
    var gradient: LinearGradient {
        let colors = isUnlocked ? rarity.colors : [Color(white: 0.32), Color(white: 0.22)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Catalogue (20 badges, 4 raretés)

enum BadgeCatalog {

    static func badges(for user: AppUser) -> [PlayerBadge] {
        let goals      = user.totalGoals
        let matches    = user.totalMatches
        let wins       = user.totalWins
        let level      = user.level
        let teams      = user.teamIds.count
        let friends    = user.friends.count
        let best       = user.bestInOneMatch
        let organized  = user.matchesOrganized ?? 0

        return [

            // ───── COMMUNS ─────
            PlayerBadge(id: "premier_match",
                        name: "Premier Coup de Sifflet",
                        description: "Jouer son premier match",
                        icon: "soccerball", shape: "circle.fill",
                        rarity: .common, target: 1, progress: matches),

            PlayerBadge(id: "premier_but",
                        name: "Premier Filet",
                        description: "Marquer son premier but",
                        icon: "star", shape: "circle.fill",
                        rarity: .common, target: 1, progress: goals),

            PlayerBadge(id: "equipe",
                        name: "En Équipe",
                        description: "Rejoindre ou créer une équipe",
                        icon: "person.3.fill", shape: "shield.fill",
                        rarity: .common, target: 1, progress: teams),

            PlayerBadge(id: "ami",
                        name: "Coéquipier",
                        description: "Avoir son premier ami",
                        icon: "person.2.fill", shape: "circle.fill",
                        rarity: .common, target: 1, progress: friends),

            PlayerBadge(id: "organisateur_debutant",
                        name: "Organisateur",
                        description: "Organiser son premier match",
                        icon: "calendar.badge.plus", shape: "shield.fill",
                        rarity: .common, target: 1, progress: organized),

            // ───── RARES ─────
            PlayerBadge(id: "hattrick",
                        name: "Hat-trick",
                        description: "Marquer 3+ buts en un seul match",
                        icon: "flame.fill", shape: "hexagon.fill",
                        rarity: .rare, target: 3, progress: best),

            PlayerBadge(id: "machine",
                        name: "Machine de Guerre",
                        description: "Jouer 10 matchs",
                        icon: "bolt.fill", shape: "diamond.fill",
                        rarity: .rare, target: 10, progress: matches),

            PlayerBadge(id: "serial_winner",
                        name: "Gagne-Pain",
                        description: "Remporter 5 matchs",
                        icon: "trophy.fill", shape: "hexagon.fill",
                        rarity: .rare, target: 5, progress: wins),

            PlayerBadge(id: "sniper",
                        name: "Sniper",
                        description: "Marquer 20 buts au total",
                        icon: "scope", shape: "shield.fill",
                        rarity: .rare, target: 20, progress: goals),

            PlayerBadge(id: "social",
                        name: "Le Connecteur",
                        description: "Avoir 5 amis",
                        icon: "network", shape: "circle.fill",
                        rarity: .rare, target: 5, progress: friends),

            // ───── ÉPIQUES ─────
            PlayerBadge(id: "veteran",
                        name: "Vétéran",
                        description: "Atteindre le niveau 20",
                        icon: "medal.fill", shape: "hexagon.fill",
                        rarity: .epic, target: 20, progress: level),

            PlayerBadge(id: "expert_orga",
                        name: "Chef d'Orchestre",
                        description: "Organiser 10 matchs",
                        icon: "calendar.badge.plus", shape: "star.fill",
                        rarity: .epic, target: 10, progress: organized),

            PlayerBadge(id: "dominateur",
                        name: "Dominateur",
                        description: "Remporter 20 matchs",
                        icon: "crown.fill", shape: "hexagon.fill",
                        rarity: .epic, target: 20, progress: wins),

            PlayerBadge(id: "buteur_elite",
                        name: "Buteur Élite",
                        description: "Marquer 50 buts au total",
                        icon: "flame.fill", shape: "diamond.fill",
                        rarity: .epic, target: 50, progress: goals),

            PlayerBadge(id: "marathonien",
                        name: "Marathonien",
                        description: "Jouer 30 matchs",
                        icon: "figure.run", shape: "shield.fill",
                        rarity: .epic, target: 30, progress: matches),

            // ───── LÉGENDAIRES ─────
            PlayerBadge(id: "legende",
                        name: "Légende",
                        description: "Marquer 100 buts au total",
                        icon: "crown.fill", shape: "star.fill",
                        rarity: .legendary, target: 100, progress: goals),

            PlayerBadge(id: "max_level",
                        name: "Niveau Max",
                        description: "Atteindre le niveau 100",
                        icon: "infinity", shape: "hexagon.fill",
                        rarity: .legendary, target: 100, progress: level),

            PlayerBadge(id: "invincible",
                        name: "Invincible",
                        description: "Remporter 50 matchs",
                        icon: "shield.fill", shape: "star.fill",
                        rarity: .legendary, target: 50, progress: wins),

            PlayerBadge(id: "quadruple",
                        name: "Tueur de Matchs",
                        description: "Marquer 4+ buts en un seul match",
                        icon: "bolt.fill", shape: "star.fill",
                        rarity: .legendary, target: 4, progress: best),

            PlayerBadge(id: "legende_orga",
                        name: "Légende Organisateur",
                        description: "Organiser 50 matchs",
                        icon: "calendar.badge.plus", shape: "hexagon.fill",
                        rarity: .legendary, target: 50, progress: organized),
        ]
    }
}
