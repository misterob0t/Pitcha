import Foundation
import FirebaseFirestore

// Extension feuille de match : chat, exclusion, votes, fin de match.
extension FirebaseService {

    // MARK: - Chat du match

    func listenMatchMessages(matchId: String, onChange: @escaping ([ChatMessage]) -> Void) -> ListenerRegistration {
        matchesRef.document(matchId).collection("messages")
            .order(by: "sentAt").limit(toLast: 100)
            .addSnapshotListener { snapshot, _ in
                let messages = snapshot?.documents.compactMap { try? $0.data(as: ChatMessage.self) } ?? []
                onChange(messages)
            }
    }

    func sendMatchMessage(matchId: String, sender: AppUser, text: String) async throws {
        guard let uid = sender.id else { return }
        let message = ChatMessage(senderId: uid, senderPseudo: sender.pseudo,
                                  text: text.trimmingCharacters(in: .whitespacesAndNewlines), sentAt: Date())
        _ = try matchesRef.document(matchId).collection("messages").addDocument(from: message)
    }

    func postMatchSystemMessage(matchId: String, text: String) async throws {
        let message = ChatMessage(senderId: "system", senderPseudo: "Système", text: text, sentAt: Date())
        _ = try matchesRef.document(matchId).collection("messages").addDocument(from: message)
    }

    // MARK: - Écoute du match en temps réel

    func listenMatch(matchId: String, onChange: @escaping (Match?) -> Void) -> ListenerRegistration {
        matchesRef.document(matchId).addSnapshotListener { snapshot, _ in
            onChange(try? snapshot?.data(as: Match.self))
        }
    }

    // MARK: - Écoute des votes en temps réel

    func listenVotes(matchId: String, onChange: @escaping ([String: String]) -> Void) -> ListenerRegistration {
        matchesRef.document(matchId).collection("votes")
            .addSnapshotListener { snapshot, _ in
                var votes: [String: String] = [:]
                snapshot?.documents.forEach { doc in
                    votes[doc.documentID] = doc.data()["vote"] as? String
                }
                onChange(votes)
            }
    }

    // MARK: - Choisir sa place sur la feuille

    func setSlot(matchId: String, uid: String, slot: Int) async throws {
        try await matchesRef.document(matchId).updateData(["slotAssignments.\(uid)": slot])
    }

    // MARK: - Exclusion d'un participant (organisateur)

    func kickParticipant(matchId: String, uid: String, pseudo: String) async throws {
        try await matchesRef.document(matchId).updateData([
            "participants": FieldValue.arrayRemove([uid])
        ])
    }

    // MARK: - Soumettre le score (→ pendingValidation)

    /// L'organisateur soumet score + buteurs. Le match passe en "pendingValidation"
    /// et les participants peuvent voter pour valider ou contester.
    func submitMatchResult(match: Match, scoreA: Int, scoreB: Int, scorers: [String: Int]) async throws {
        guard let matchId = match.id else { return }
        let now = Date()
        // Passer en pendingValidation : les participants votent pour valider
        try await matchesRef.document(matchId).updateData([
            "status": MatchStatus.pendingValidation.rawValue,
            "scoreA": scoreA,
            "scoreB": scoreB,
            "scorers": scorers,
            "scoreSubmittedAt": Timestamp(date: now)
        ])
        try await postMatchSystemMessage(matchId: matchId, text: "⏳ Score soumis : \(scoreA) – \(scoreB). Votez pour valider !")
        await MainActor.run {
            BackgroundTaskService.shared.scheduleMatchTimeoutCheck(submittedAt: now)
        }
    }

    // MARK: - Voter (participant)

    func voteMatch(matchId: String, uid: String, validate: Bool) async throws {
        let voteValue = validate ? "validate" : "contest"
        try await matchesRef.document(matchId).collection("votes").document(uid).setData([
            "vote": voteValue,
            "timestamp": Timestamp(date: Date())
        ])
        // Vérifier si le seuil est atteint après ce vote
        try await checkValidationThreshold(matchId: matchId)
    }

    // MARK: - Vérification du seuil de validation

    /// Appelée après chaque vote. Utilise une transaction pour éviter la
    /// double-distribution si plusieurs clients franchissent le seuil en même temps.
    func checkValidationThreshold(matchId: String) async throws {
        // Récupérer les votes et le match
        let votesSnap = try await matchesRef.document(matchId).collection("votes").getDocuments()
        let matchSnap = try await matchesRef.document(matchId).getDocument()
        guard let match = try? matchSnap.data(as: Match.self),
              match.status == .pendingValidation else { return }

        let totalParticipants = match.participants.count
        guard totalParticipants > 0 else { return }

        var validateCount = 0
        var contestCount = 0
        votesSnap.documents.forEach { doc in
            switch doc.data()["vote"] as? String {
            case "validate": validateCount += 1
            case "contest":  contestCount += 1
            default: break
            }
        }

        let validateRatio = Double(validateCount) / Double(totalParticipants)
        let contestRatio  = Double(contestCount)  / Double(totalParticipants)

        // Seuil adaptatif : 50% pour ≤4 joueurs, 75% au-delà
        let threshold = totalParticipants <= 4 ? 0.50 : 0.75
        if validateRatio >= threshold {
            // Majorité validante : XP complète
            try await finalizeMatch(match: match, reductionFactor: 1.0, contested: false)
        } else if contestRatio > 0.30 {
            // Majorité contestante : XP réduite du taux de contestation
            let reduction = max(0.3, 1.0 - contestRatio)
            try await finalizeMatch(match: match, reductionFactor: reduction, contested: true)
        }
        // Sinon : en attente de plus de votes ou timeout 48h
    }

    // MARK: - Finalisation (clôture du match + distribution XP)

    private func finalizeMatch(match: Match, reductionFactor: Double, contested: Bool) async throws {
        guard let matchId = match.id, let scoreA = match.scoreA, let scoreB = match.scoreB else { return }
        let newStatus = contested ? MatchStatus.contested : MatchStatus.played

        // Transaction : vérifie que le statut est encore pendingValidation avant de clôturer
        let matchRef = matchesRef.document(matchId)
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let snap = try transaction.getDocument(matchRef)
                let currentStatus = snap.data()?["status"] as? String ?? ""
                guard currentStatus == MatchStatus.pendingValidation.rawValue else {
                    // Déjà finalisé par un autre client, on abandonne silencieusement
                    return nil
                }
                transaction.updateData(["status": newStatus.rawValue], forDocument: matchRef)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }

        // Distribution XP avec facteur de réduction
        let scorers = match.scorers ?? [:]
        let title = "Match \(match.type.displayName) • \(scoreA)–\(scoreB)"
        for uid in match.participants {
            let side = match.side(of: uid) ?? 0
            let myScore    = side == 0 ? scoreA : scoreB
            let theirScore = side == 0 ? scoreB : scoreA
            let won   = myScore > theirScore
            let drawn = myScore == theirScore
            let goals = scorers[uid] ?? 0
            try await awardMatchResultReduced(uid: uid, won: won, drawn: drawn, goals: goals,
                                             title: title, factor: reductionFactor)
        }

        let emoji = contested ? "⚠️" : "🏁"
        let msg = contested
            ? "\(emoji) Match contesté (\(Int(reductionFactor * 100))% de l'XP distribué)"
            : "\(emoji) Résultat validé ! Score : \(scoreA) – \(scoreB)"
        try await postMatchSystemMessage(matchId: matchId, text: msg)
    }

    // MARK: - Distribution XP avec facteur de réduction
    // Réutilise awardMatchResult existant (transactions + MatchRecord en String).
    // Le facteur réduit uniquement l'XP via XPSystem.xpGain (on patch temporairement
    // via une surcharge locale qui applique le ratio après calcul).
    private func awardMatchResultReduced(uid: String, won: Bool, drawn: Bool, goals: Int,
                                         title: String, factor: Double) async throws {
        guard factor >= 1.0 else {
            // XP réduite : on applique la transaction manuellement
            let userDoc = usersRef.document(uid)
            let historyDoc = userDoc.collection("history").document()
            _ = try await db.runTransaction { transaction, errorPointer in
                do {
                    let snap = try transaction.getDocument(userDoc)
                    guard let user = try? snap.data(as: AppUser.self) else { throw PitchaError.dataCorrupted }
                    let oldLevel = XPSystem.level(forXP: user.xp)
                    let baseXP = XPSystem.xpGain(won: won, goals: goals)
                    let xpGained = Int(Double(baseXP) * factor)
                    let newXP = min(user.xp + xpGained, XPSystem.maxXP)
                    let newLevel = XPSystem.level(forXP: newXP)
                    let gainedSP = max(0, newLevel - oldLevel) * XPSystem.skillPointsPerLevel
                    let result = won ? "win" : (drawn ? "draw" : "loss")
                    transaction.updateData([
                        "xp": newXP,
                        "skillPoints": user.skillPoints + gainedSP,
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
            return
        }
        // XP complète (factor == 1.0) : déléguer à awardMatchResult standard
        try await awardMatchResult(uid: uid, won: won, drawn: drawn, goals: goals, title: title)
    }

    // MARK: - Timeout 48h (auto-distribution à 80%)

    /// À appeler au démarrage de la vue feuille de match si le match est
    /// en pendingValidation depuis plus de 48h.
    func checkTimeoutDistribution(match: Match) async throws {
        guard match.status == .pendingValidation,
              let submittedAt = match.scoreSubmittedAt,
              Date().timeIntervalSince(submittedAt) > 48 * 3600 else { return }
        try await finalizeMatch(match: match, reductionFactor: 0.8, contested: false)
    }

    // MARK: - Annulation

    func cancelMatch(matchId: String) async throws {
        try await matchesRef.document(matchId).updateData(["status": MatchStatus.cancelled.rawValue])
    }
}
