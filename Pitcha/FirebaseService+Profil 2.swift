import Foundation
import FirebaseAuth
import FirebaseFirestore

// Extension profil : sous-attributs, résultat de match (XP + level up + historique),
// infos personnelles, photo. Tout sauf l'historique vit sur users/{uid}.
extension FirebaseService {

    func saveSubAttributes(uid: String, subAttributes: SubAttributes, skillPoints: Int) async throws {
        try await usersRef.document(uid).updateData([
            "subAttributes": subAttributes.asDictionary,
            "skillPoints": skillPoints
        ])
    }

    /// Applique le résultat d'un match : XP (+500 participation, +1500 victoire,
    /// +500/but), stats, +2 skill points par niveau gagné, meilleur score en un
    /// match, et UNE entrée d'historique. Le tout dans une transaction atomique.
    func awardMatchResult(uid: String, won: Bool, drawn: Bool, goals: Int, title: String = "Match") async throws {
        let userDoc = usersRef.document(uid)
        let historyDoc = userDoc.collection("history").document()

        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let snap = try transaction.getDocument(userDoc)
                guard let user = try? snap.data(as: AppUser.self) else {
                    throw PitchaError.dataCorrupted
                }

                let oldLevel = XPSystem.level(forXP: user.xp)
                let xpGained = XPSystem.xpGain(won: won, goals: goals)
                // Niveau 100 = fin de saison : l'XP n'augmente plus
                let newXP = min(user.xp + xpGained, XPSystem.maxXP)
                let newLevel = XPSystem.level(forXP: newXP)
                let gainedSkillPoints = max(0, newLevel - oldLevel) * XPSystem.skillPointsPerLevel
                let result = won ? "win" : (drawn ? "draw" : "loss")

                transaction.updateData([
                    "xp": newXP,
                    "skillPoints": user.skillPoints + gainedSkillPoints,
                    "matchesPlayed": user.totalMatches + 1,
                    "goals": user.totalGoals + goals,
                    "wins": user.totalWins + (won ? 1 : 0),
                    "draws": user.totalDraws + (drawn ? 1 : 0),
                    "losses": user.totalLosses + (!won && !drawn ? 1 : 0),
                    "bestGoalsInMatch": max(user.bestInOneMatch, goals)
                ], forDocument: userDoc)

                transaction.setData([
                    "date": Timestamp(date: Date()),
                    "title": title,
                    "goals": goals,
                    "result": result,
                    "xpGained": xpGained
                ], forDocument: historyDoc)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    /// Historique des matchs joués, du plus récent au plus ancien.
    func fetchHistory(uid: String) async throws -> [MatchRecord] {
        let snapshot = try await usersRef.document(uid)
            .collection("history")
            .order(by: "date", descending: true)
            .limit(to: 100)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: MatchRecord.self) }
    }

    /// Photo de profil : base64 (200px, jpeg 0.7) directement dans Firestore.
    /// Pas de Firebase Storage requis ; migration possible plus tard.
    func savePhoto(uid: String, base64: String) async throws {
        try await usersRef.document(uid).updateData(["photoBase64": base64])
    }

    /// Envoie l'email de réinitialisation de mot de passe Firebase.
    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func updatePersonalInfo(uid: String, heightCm: Int?, weightKg: Int?, favoriteTeam: String?, strongFoot: StrongFoot?) async throws {
        var fields: [String: Any] = [:]
        fields["heightCm"] = heightCm ?? FieldValue.delete()
        fields["weightKg"] = weightKg ?? FieldValue.delete()
        fields["favoriteTeam"] = (favoriteTeam?.isEmpty == false ? favoriteTeam : FieldValue.delete()) as Any
        fields["strongFoot"] = strongFoot?.rawValue ?? FieldValue.delete()
        try await usersRef.document(uid).updateData(fields)
    }
}
