import Foundation
import FirebaseFirestore

// Extension classement : top joueurs + rang exact.
extension FirebaseService {

    /// ⚠️ Coûteux (50 lectures + 1 agrégation à chaque appel) : utilisé
    /// uniquement en repli si le classement précalculé est absent/trop vieux.
    func fetchLeaderboard(limit: Int = 50) async throws -> [AppUser] {
        let snapshot = try await usersRef
            .order(by: "xp", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: AppUser.self) }
    }

    /// Classement précalculé par une Cloud Function planifiée (toutes les
    /// 15 min) : UNE seule lecture au lieu de 50+ à chaque ouverture de
    /// l'écran Classement. Retourne nil si le document n'existe pas encore
    /// (premier déploiement) ou s'il est trop ancien (>30 min, signe que la
    /// Cloud Function a un problème) — dans ce cas on retombe sur le calcul
    /// live côté client via fetchLeaderboard.
    ///
    /// Reconstruit de vrais AppUser légers (champs d'affichage uniquement)
    /// pour rester 100% compatible avec RankRow/AvatarImage sans toucher
    /// à la vue Classement.
    func fetchPrecomputedLeaderboard() async throws -> [AppUser]? {
        let doc = try await db.collection("leaderboard").document("top").getDocument()
        guard let data = doc.data(),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue(),
              Date().timeIntervalSince(updatedAt) < 30 * 60,
              let rawPlayers = data["players"] as? [[String: Any]] else {
            return nil
        }
        return rawPlayers.compactMap { dict -> AppUser? in
            guard let uid = dict["uid"] as? String,
                  let pseudo = dict["pseudo"] as? String else { return nil }
            var user = AppUser(
                id: uid,
                pseudo: pseudo,
                email: "",
                coins: 0,
                xp: dict["xp"] as? Int ?? 0,
                skillPoints: 0,
                position: .mil,
                attributes: .base,
                friends: [],
                teamIds: [],
                createdAt: Date()
            )
            user.photoURL = dict["photoURL"] as? String
            user.goals = dict["goals"] as? Int
            user.wins = dict["wins"] as? Int
            user.draws = dict["draws"] as? Int
            user.losses = dict["losses"] as? Int
            user.matchesPlayed = dict["matchesPlayed"] as? Int
            return user
        }
    }

    /// Rang exact par buts : nombre de joueurs avec plus de buts + 1.
    /// Agrégation count = 1 lecture facturée. Les comptes sans champ "goals"
    /// sont exclus de l'inégalité, donc comptés comme 0 but : correct.
    func fetchRankByGoals(goals: Int) async throws -> Int {
        let query = usersRef.whereField("goals", isGreaterThan: goals)
        let snapshot = try await query.count.getAggregation(source: .server)
        return snapshot.count.intValue + 1
    }

    /// Classement Régional : uniquement les joueurs de la même ville que
    /// l'utilisateur (champ "city", choisi à l'inscription). Requête live
    /// (pas de précalcul possible ville par ville sans exploser le nombre
    /// de documents précalculés) — reste peu coûteux car une ville donnée
    /// ne compte qu'une fraction des utilisateurs totaux.
    ///
    /// ⚠️ Nécessite un index composite Firestore (city + xp descending).
    /// Au premier appel, Firestore renvoie une erreur avec un lien direct
    /// pour créer cet index automatiquement dans la console — clique dessus,
    /// l'index se crée en quelques minutes.
    func fetchRegionalLeaderboard(city: String, limit: Int = 50) async throws -> [AppUser] {
        let snapshot = try await usersRef
            .whereField("city", isEqualTo: city)
            .order(by: "xp", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: AppUser.self) }
    }

    /// Rang exact par buts, restreint à une ville — même principe que
    /// fetchRankByGoals mais filtré, pour que le rang affiché en Régional
    /// reste cohérent avec la liste régionale (pas un rang national).
    func fetchRegionalRankByGoals(city: String, goals: Int) async throws -> Int {
        let query = usersRef
            .whereField("city", isEqualTo: city)
            .whereField("goals", isGreaterThan: goals)
        let snapshot = try await query.count.getAggregation(source: .server)
        return snapshot.count.intValue + 1
    }
}
