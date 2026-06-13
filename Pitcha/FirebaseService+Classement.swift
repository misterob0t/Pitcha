import Foundation
import FirebaseFirestore

// Extension classement : top joueurs + rang exact.
extension FirebaseService {

    /// Top joueurs triés par XP décroissant (le champ xp existe sur tous les
    /// comptes, contrairement à goals). Le tri par buts se fait côté client.
    func fetchLeaderboard(limit: Int = 50) async throws -> [AppUser] {
        let snapshot = try await usersRef
            .order(by: "xp", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: AppUser.self) }
    }

    /// Rang exact par buts : nombre de joueurs avec plus de buts + 1.
    /// Agrégation count = 1 lecture facturée. Les comptes sans champ "goals"
    /// sont exclus de l'inégalité, donc comptés comme 0 but : correct.
    func fetchRankByGoals(goals: Int) async throws -> Int {
        let query = usersRef.whereField("goals", isGreaterThan: goals)
        let snapshot = try await query.count.getAggregation(source: .server)
        return snapshot.count.intValue + 1
    }
}
