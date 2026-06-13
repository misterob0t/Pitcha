import Foundation
import Combine

enum RankScope: String, CaseIterable, Identifiable {
    case regional = "Régional"
    case national = "National"
    case mondial = "Mondial"

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

    // TODO (ajustements) : filtrer par région/pays quand le champ existera
    // sur le profil. Pour l'instant les 3 scopes affichent le global.
    func load(user: AppUser?) async {
        isLoading = players.isEmpty
        errorMessage = nil
        do {
            let fetched = try await service.fetchLeaderboard(limit: 50)
            // Classement par buts, départagé par XP
            players = fetched.sorted {
                ($0.totalGoals, $0.xp) > ($1.totalGoals, $1.xp)
            }
            if let user {
                if let index = players.firstIndex(where: { $0.id == user.id }) {
                    myRank = index + 1
                } else {
                    myRank = try await service.fetchRankByGoals(goals: user.totalGoals)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func isMe(_ player: AppUser, user: AppUser?) -> Bool {
        player.id != nil && player.id == user?.id
    }

    /// Vrai si l'utilisateur n'apparaît pas dans le top affiché.
    func isOutsideTop(user: AppUser?) -> Bool {
        guard let uid = user?.id else { return false }
        return !players.contains { $0.id == uid }
    }
}

// MARK: - Badges (calculés localement depuis les stats)

struct PlayerBadge: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let shape: String   // SF Symbol de fond : hexagon.fill, shield.fill, star.fill, diamond.fill...
    let target: Int
    let progress: Int

    var isUnlocked: Bool { progress >= target }
    var clampedProgress: Int { min(progress, target) }
}

enum BadgeCatalog {
    static func badges(for user: AppUser) -> [PlayerBadge] {
        [
            PlayerBadge(id: "hattrick", name: "Hat-trick",
                        description: "Marquer 3 buts en 1 match",
                        icon: "flame.fill", shape: "hexagon.fill",
                        target: 3, progress: user.bestInOneMatch),
            PlayerBadge(id: "organisateur", name: "Organisateur",
                        description: "Organiser 3 matchs",
                        icon: "calendar.badge.plus", shape: "shield.fill",
                        target: 3, progress: 0), // TODO : tracker les matchs organisés
            PlayerBadge(id: "legende", name: "Légende",
                        description: "Marquer 50 buts au total",
                        icon: "crown.fill", shape: "star.fill",
                        target: 50, progress: user.totalGoals),
            PlayerBadge(id: "machine", name: "Machine",
                        description: "Jouer 10 matchs",
                        icon: "bolt.fill", shape: "diamond.fill",
                        target: 10, progress: user.totalMatches),
            PlayerBadge(id: "capitaine", name: "Capitaine",
                        description: "Rejoindre ou créer une équipe",
                        icon: "person.3.fill", shape: "seal.fill",
                        target: 1, progress: user.teamIds.count),
            PlayerBadge(id: "veteran", name: "Vétéran",
                        description: "Atteindre le niveau 10",
                        icon: "medal.fill", shape: "hexagon.fill",
                        target: 10, progress: user.level)
        ]
    }
}
