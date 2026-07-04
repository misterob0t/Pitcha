import Foundation
import Combine
import FirebaseFirestore

enum MatchVisibility: String, CaseIterable {
    case publics = "Publics"
    case prives = "Privés"
    case tournois = "Tournois"
}

@MainActor
final class MatchsViewModel: ObservableObject {

    @Published var matches: [Match] = []
    @Published var selectedDate = Calendar.current.startOfDay(for: Date())
    @Published var visibility: MatchVisibility = .publics
    @Published var selectedType: MatchType?    // nil = tous les types
    @Published var city = "Paris"
    @Published var errorMessage: String?
    @Published var isWorking = false

    static let cities = ["Paris", "Lyon", "Nantes", "Marseille", "Lille", "Bordeaux"]

    private let service = FirebaseService.shared
    private var refreshTask: Task<Void, Never>?
    private let calendar = Calendar.current

    deinit {
        refreshTask?.cancel()
    }

    // MARK: - Rafraîchissement périodique (coût borné, pas un listener fan-out)
    //
    // Lecture ponctuelle au lieu d'un listener temps réel sur la liste
    // complète : le coût ne dépend plus que du nombre d'écrans ouverts,
    // jamais multiplié par l'activité de TOUS les autres utilisateurs
    // ailleurs dans l'app. La fraîcheur perçue reste excellente (max 20s
    // de délai) pour un coût strictement borné.

    /// À appeler quand l'écran Matchs apparaît (.onAppear).
    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    /// À appeler quand l'écran Matchs disparaît (.onDisappear) — indispensable
    /// pour ne pas continuer à consommer des lectures en arrière-plan.
    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Lecture immédiate (tirer pour rafraîchir, ou à l'ouverture de l'écran).
    func refreshNow() async {
        do {
            matches = try await service.fetchOpenMatches()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Compat : ancien nom, redirige vers le nouveau système.
    func listen() {
        startAutoRefresh()
    }

    // MARK: - Strip de jours (14 prochains jours)

    var upcomingDays: [Date] {
        (0..<14).compactMap {
            calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: Date()))
        }
    }

    func isSelected(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: selectedDate)
    }

    // MARK: - Filtres

    var filteredMatches: [Match] {
        // Tournois : fonctionnalité à venir, aucun match de ce type n'existe
        // encore côté données — on retourne une liste vide plutôt que de
        // mal filtrer des matchs publics/privés dans cet onglet.
        guard visibility != .tournois else { return [] }

        return matches.filter { match in
            let dayOK = calendar.isDate(match.date, inSameDayAs: selectedDate)
            let visibilityOK = (visibility == .prives) == match.isPrivateMatch
            let typeOK = selectedType.map { match.type == $0 } ?? true
            let cityOK = (match.zone?.localizedCaseInsensitiveContains(city) ?? false)
                || match.location.localizedCaseInsensitiveContains(city)
            return dayOK && visibilityOK && typeOK && cityOK
        }
    }

    // MARK: - Actions

    func join(_ match: Match, uid: String?) async {
        guard let matchId = match.id, let uid else { return }
        await run { try await self.service.joinMatch(matchId: matchId, uid: uid) }
    }

    func leave(_ match: Match, uid: String?) async {
        guard let matchId = match.id, let uid else { return }
        await run { try await self.service.leaveMatch(matchId: matchId, uid: uid) }
    }

    func cancel(_ match: Match) async {
        guard let matchId = match.id else { return }
        await run { try await self.service.cancelMatch(matchId: matchId) }
    }

    func create(
        type: MatchType,
        isPrivate: Bool,
        date: Date,
        maxPlayers: Int,
        zone: String,
        address: String,
        tag: MatchTag = .mixte,
        organizer: AppUser
    ) async -> Bool {
        guard let uid = organizer.id else { return false }
        let match = Match(
            organizerId: uid,
            organizerPseudo: organizer.pseudo,
            type: type,
            location: address.trimmingCharacters(in: .whitespaces),
            date: date,
            maxPlayers: maxPlayers,
            participants: [uid],
            status: .open,
            teamId: nil,
            isPrivate: isPrivate,
            tag: tag.rawValue,
            zone: zone.trimmingCharacters(in: .whitespaces),
            createdAt: Date()
        )
        var success = false
        await run {
            try await self.service.createMatchWithIntegrityCheck(match, organizer: organizer)
            success = true
        }
        if success {
            // Synchronise les filtres actifs avec le match créé : sans ça, le
            // match pourrait exister en base mais rester invisible dans la
            // liste (mauvais jour sélectionné, mauvaise visibilité, etc.),
            // ce qui donnerait l'impression qu'il a disparu.
            selectedDate = calendar.startOfDay(for: date)
            visibility = isPrivate ? .prives : .publics
            if !zone.trimmingCharacters(in: .whitespaces).isEmpty {
                city = zone.trimmingCharacters(in: .whitespaces)
            }
            selectedType = nil // évite qu'un filtre de type masque le match

            // Recharge immédiate : le match créé apparaît sans attendre le
            // cycle auto-refresh (20s) ni un tiré-pour-rafraîchir manuel.
            await refreshNow()
        }
        return success
    }

    // MARK: - Helper

    private func run(_ block: @escaping () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        do {
            try await block()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}
