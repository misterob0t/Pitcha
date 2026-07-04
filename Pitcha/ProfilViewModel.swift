import Foundation
import Combine
import UIKit

@MainActor
final class ProfilViewModel: ObservableObject {

    /// Points dépensés localement (brouillon), par SOUS-attribut.
    /// Rien n'est écrit en base tant que l'utilisateur n'a pas validé.
    @Published var spent: [String: Int] = [:]
    @Published var errorMessage: String?
    @Published var isWorking = false
    @Published var saveSucceeded = false

    private let service = FirebaseService.shared

    // MARK: - Lecture du brouillon (sous-attributs)

    func draftValue(forSub key: String, user: AppUser) -> Int {
        min(99, user.subs.value(for: key) + (spent[key] ?? 0))
    }

    /// Sous-attributs avec le brouillon appliqué (pour les moyennes live).
    func draftSubs(user: AppUser) -> SubAttributes {
        var subs = user.subs
        for (key, points) in spent {
            subs.add(points, to: key)
        }
        return subs
    }

    func draftMainValue(for mainKey: String, user: AppUser) -> Int {
        let subs = draftSubs(user: user)
        switch mainKey {
        case "VIT": return subs.vit
        case "TIR": return subs.tir
        case "PAS": return subs.pas
        case "DRI": return subs.dri
        case "DEF": return subs.def
        case "PHY": return subs.phy
        default: return 0
        }
    }

    func totalSpent() -> Int {
        spent.values.reduce(0, +)
    }

    func remainingPoints(user: AppUser) -> Int {
        max(0, user.skillPoints - totalSpent())
    }

    var hasPendingChanges: Bool {
        totalSpent() > 0
    }

    // MARK: - Modification du brouillon

    func addPoint(toSub key: String, user: AppUser) {
        guard remainingPoints(user: user) > 0 else { return }
        guard draftValue(forSub: key, user: user) < 99 else { return }
        spent[key, default: 0] += 1
    }

    func removePoint(fromSub key: String) {
        guard let current = spent[key], current > 0 else { return }
        spent[key] = current - 1
        if spent[key] == 0 { spent[key] = nil }
    }

    func resetDraft() {
        spent = [:]
    }

    // MARK: - Sauvegarde

    func save(user: AppUser) async {
        guard let uid = user.id, hasPendingChanges else { return }

        let newSubs = draftSubs(user: user)
        let newSkillPoints = max(0, user.skillPoints - totalSpent())

        isWorking = true
        errorMessage = nil
        do {
            try await service.saveSubAttributes(uid: uid, subAttributes: newSubs, skillPoints: newSkillPoints)
            spent = [:]
            saveSucceeded.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    // MARK: - Position

    func updatePosition(_ position: PlayerPosition, user: AppUser) async {
        guard let uid = user.id else { return }
        do {
            try await service.updateUser(uid: uid, fields: ["position": position.rawValue])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Photo de profil (200px, jpeg 0.7, base64 dans Firestore)

    func savePhoto(_ image: UIImage, user: AppUser) async {
        guard let uid = user.id else { return }
        do {
            // Upload vers Firebase Storage (plus de base64 dans Firestore :
            // ça évite de facturer la lecture de la photo à chaque lecture
            // du profil, même quand elle n'est pas affichée).
            _ = try await service.uploadProfilePhoto(uid: uid, image: image)
            saveSucceeded.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Historique des matchs

    @Published var history: [MatchRecord] = []
    @Published var historyLoading = false

    func loadHistory(user: AppUser) async {
        guard let uid = user.id else { return }
        historyLoading = history.isEmpty
        do {
            history = try await service.fetchHistory(uid: uid)
        } catch {
            errorMessage = error.localizedDescription
        }
        historyLoading = false
    }

    // MARK: - Infos perso (dos de la carte)

    func savePersonalInfo(user: AppUser, heightCm: Int?, weightKg: Int?, favoriteTeam: String, strongFoot: StrongFoot) async {
        guard let uid = user.id else { return }
        isWorking = true
        do {
            try await service.updatePersonalInfo(
                uid: uid,
                heightCm: heightCm,
                weightKg: weightKg,
                favoriteTeam: favoriteTeam,
                strongFoot: strongFoot
            )
            saveSucceeded.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    // MARK: - Titre (style LoL)

    func saveTitle(_ title: String, user: AppUser) async {
        guard let uid = user.id else { return }
        do {
            try await service.updateUser(uid: uid, fields: [
                "title": title.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Changement de mot de passe

    func sendPasswordReset(email: String) async {
        do {
            try await service.sendPasswordReset(email: email)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Debug (simulateur uniquement)

    #if DEBUG
    /// Simule un match joué via le vrai pipeline XP (awardMatchResult) :
    /// +500 participation, +1500 si victoire, +500/but, +2 pts par level up.
    func debugSimulateMatch(user: AppUser) async {
        guard let uid = user.id else { return }
        let goalsScored = Int.random(in: 0...4)
        let result = Int.random(in: 0...2) // 0 victoire, 1 nul, 2 défaite
        do {
            try await service.awardMatchResult(
                uid: uid,
                won: result == 0,
                drawn: result == 1,
                goals: goalsScored
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    #endif
}
