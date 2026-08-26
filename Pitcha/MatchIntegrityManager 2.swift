import Foundation
import FirebaseFirestore

// MARK: - Erreurs d'intégrité

enum MatchIntegrityError: LocalizedError {
    case matchCreationLimitReached(quota: Int)

    var errorDescription: String? {
        switch self {
        case .matchCreationLimitReached(let quota):
            return "Limite atteinte : \(quota) match\(quota > 1 ? "s" : "") max par 24h à ton niveau. Monte de niveau pour en créer plus !"
        }
    }
}

// MARK: - Manager d'intégrité (quota journalier)

final class MatchIntegrityManager {
    static let shared = MatchIntegrityManager()
    private init() {}

    /// Quota de créations de match par 24h glissantes selon le niveau.
    static func dailyQuota(forLevel level: Int) -> Int {
        if level >= 50 { return 4 }
        if level >= 10 { return 3 }
        return 2
    }

    // MARK: - Règles de clôture

    enum ClosureError: LocalizedError {
        case tooEarly(availableAt: Date), notFull
        var errorDescription: String? {
            switch self {
            case .tooEarly(let availableAt):
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "fr_FR")
                formatter.dateFormat = "HH:mm"
                return "Clôture disponible à partir de \(formatter.string(from: availableAt)) (1h après le début du match)."
            case .notFull:
                return "Le match doit être complet (tous les joueurs confirmés) pour être clôturé."
            }
        }
    }

    /// Vérifie les deux règles de clôture avant d'afficher la saisie du score.
    /// Vérifie les deux règles de clôture avant d'afficher la saisie du score.
    static func checkClosureEligibility(_ match: Match) throws {
        let oneHourAfterStart = match.date.addingTimeInterval(3600)
        guard Date() > oneHourAfterStart else {
            throw ClosureError.tooEarly(availableAt: oneHourAfterStart)
        }
        guard match.participants.count == match.maxPlayers else { throw ClosureError.notFull }
    }

    /// Vérifie le quota 24h glissant. Un seul whereField (organizerId) =
    /// AUCUN index composite requis ; la fenêtre 24h est comptée côté client
    /// (un organisateur a peu de matchs, le coût est négligeable).
    func checkMatchCreationQuota(userId: String, userLevel: Int) async throws {
        let quota = Self.dailyQuota(forLevel: userLevel)
        let since = Date().addingTimeInterval(-24 * 3600)

        let snapshot = try await FirebaseService.shared.matchesRef
            .whereField("organizerId", isEqualTo: userId)
            .getDocuments()

        let createdLast24h = snapshot.documents.filter { doc in
            let createdAt = (doc.data()["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
            return createdAt > since
        }.count

        guard createdLast24h < quota else {
            throw MatchIntegrityError.matchCreationLimitReached(quota: quota)
        }
    }
}

// MARK: - Création avec vérification d'intégrité

extension FirebaseService {

    static let matchCreationCost = 1  // 🪙 coût en coins pour créer un match

    /// Crée un match après vérification du quota, en débitant 1 coin.
    /// La déduction du coin et la création du document se font dans la MÊME
    /// transaction : si l'une échoue, l'autre est annulée — aucun remboursement
    /// à gérer, l'état incohérent est impossible.
    func createMatchWithIntegrityCheck(_ match: Match, organizer: AppUser) async throws {
        guard let uid = organizer.id else { throw PitchaError.dataCorrupted }

        // 1️⃣ Quota journalier selon le niveau
        let level = XPSystem.level(forXP: organizer.xp)
        try await MatchIntegrityManager.shared.checkMatchCreationQuota(userId: uid, userLevel: level)

        // 2️⃣ Transaction atomique : solde -> débit + création
        let matchDoc = matchesRef.document()
        let userDoc = usersRef.document(uid)

        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let snap = try transaction.getDocument(userDoc)
                guard let user = try? snap.data(as: AppUser.self) else {
                    throw PitchaError.dataCorrupted
                }
                guard user.coins >= FirebaseService.matchCreationCost else {
                    throw PitchaError.notEnoughCoins
                }

                try transaction.setData(from: match, forDocument: matchDoc)
                transaction.updateData([
                    "coins": FieldValue.increment(Int64(-FirebaseService.matchCreationCost)),
                    "matchesOrganized": FieldValue.increment(Int64(1))
                ], forDocument: userDoc)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }
}
