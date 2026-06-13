import Foundation
import Combine
import FirebaseFirestore

enum MatchVisibility: String, CaseIterable {
    case publics = "Publics"
    case prives = "Privés"
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

    static let cities = ["Paris", "Meaux", "Lyon", "Marseille", "Lille", "Bordeaux"]

    private let service = FirebaseService.shared
    private var listener: ListenerRegistration?
    private let calendar = Calendar.current

    init() {
        listen()
    }

    deinit {
        listener?.remove()
    }

    // MARK: - Listener temps réel

    func listen() {
        listener?.remove()
        listener = service.listenOpenMatches { [weak self] matches in
            Task { @MainActor in self?.matches = matches }
        }
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
        matches.filter { match in
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
            zone: zone.trimmingCharacters(in: .whitespaces),
            createdAt: Date()
        )
        var success = false
        await run {
            try await self.service.createMatchWithIntegrityCheck(match, organizer: organizer)
            success = true
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
