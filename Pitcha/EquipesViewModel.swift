import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class EquipesViewModel: ObservableObject {

    @Published var teams: [Team] = []
    @Published var errorMessage: String?
    @Published var isWorking = false

    private let service = FirebaseService.shared
    private var listener: ListenerRegistration?

    deinit {
        listener?.remove()
    }

    func listen(uid: String?) {
        guard let uid else { return }
        listener?.remove()
        listener = service.listenTeams(forUser: uid) { [weak self] teams in
            Task { @MainActor in
                self?.teams = teams.sorted { $0.createdAt > $1.createdAt }
            }
        }
    }

    /// Crée l'équipe avec les amis sélectionnés comme membres initiaux.
    func createTeam(name: String, ownerId: String?, memberIds: [String], crestIcon: String, crestColorName: String) async -> Bool {
        guard let ownerId else { return false }
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        guard cleanName.count >= 3 else {
            errorMessage = "Le nom doit faire au moins 3 caractères."
            return false
        }
        isWorking = true
        errorMessage = nil
        var success = false
        do {
            try await service.createTeamWithMembers(name: cleanName, ownerId: ownerId, memberIds: memberIds, crestIcon: crestIcon, crestColorName: crestColorName)
            success = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
        return success
    }
}
