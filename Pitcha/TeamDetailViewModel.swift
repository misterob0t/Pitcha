import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class TeamDetailViewModel: ObservableObject {

    @Published var members: [AppUser] = []
    @Published var messages: [ChatMessage] = []
    @Published var teamMatches: [Match] = []
    @Published var inviteResult: String?
    @Published var errorMessage: String?
    @Published var isWorking = false

    private let service = FirebaseService.shared
    private var messagesListener: ListenerRegistration?
    private var teamListener: ListenerRegistration?
    private var matchesListener: ListenerRegistration?

    deinit {
        messagesListener?.remove()
        teamListener?.remove()
        matchesListener?.remove()
    }

    // MARK: - Listeners

    func listen(team: Team) {
        guard let teamId = team.id else { return }

        messagesListener?.remove()
        messagesListener = service.listenTeamMessages(teamId: teamId) { [weak self] messages in
            Task { @MainActor in self?.messages = messages }
        }

        matchesListener?.remove()
        matchesListener = service.listenTeamMatches(teamId: teamId) { [weak self] matches in
            Task { @MainActor in self?.teamMatches = matches }
        }

        // Écoute le doc équipe pour recharger les membres quand la liste change
        teamListener?.remove()
        teamListener = service.teamsRef.document(teamId).addSnapshotListener { [weak self] snapshot, _ in
            guard let team = try? snapshot?.data(as: Team.self) else { return }
            Task { @MainActor in
                await self?.loadMembers(uids: team.memberIds)
            }
        }
    }

    private func loadMembers(uids: [String]) async {
        do {
            let users = try await service.fetchUsers(uids: uids)
            // Tri stable : ordre d'arrivée dans l'équipe
            members = uids.compactMap { uid in users.first { $0.id == uid } }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Chat

    func send(text: String, team: Team, sender: AppUser?) async {
        guard let teamId = team.id, let sender else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        do {
            try await service.sendTeamMessage(teamId: teamId, sender: sender, text: clean)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Membres

    func invite(pseudo: String, team: Team) async {
        guard let teamId = team.id else { return }
        isWorking = true
        inviteResult = nil
        do {
            guard let user = try await service.findUser(pseudo: pseudo) else {
                inviteResult = "Aucun joueur trouvé avec ce pseudo."
                isWorking = false
                return
            }
            guard let uid = user.id else { return }
            guard !team.memberIds.contains(uid) else {
                inviteResult = "\(user.pseudo) est déjà dans l'équipe."
                isWorking = false
                return
            }
            try await service.addTeamMember(teamId: teamId, uid: uid)
            inviteResult = "\(user.pseudo) a rejoint l'équipe ✓"
        } catch {
            inviteResult = error.localizedDescription
        }
        isWorking = false
    }

    /// Ajout depuis la liste d'amis — uid déjà connu, plus besoin de
    /// rechercher par pseudo (voir InvitePlayerSheet, reconstruite pour
    /// montrer les amis directement plutôt qu'un champ de recherche libre).
    func inviteFriend(uid: String, pseudo: String, team: Team) async {
        guard let teamId = team.id else { return }
        isWorking = true
        inviteResult = nil
        guard !team.memberIds.contains(uid) else {
            inviteResult = "\(pseudo) est déjà dans l'équipe."
            isWorking = false
            return
        }
        do {
            try await service.addTeamMember(teamId: teamId, uid: uid)
            inviteResult = "\(pseudo) a rejoint l'équipe ✓"
        } catch {
            inviteResult = error.localizedDescription
        }
        isWorking = false
    }

    func removeMember(uid: String, team: Team) async {
        guard let teamId = team.id else { return }
        do {
            try await service.removeTeamMember(teamId: teamId, uid: uid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func leaveTeam(team: Team, uid: String?) async {
        guard let teamId = team.id, let uid else { return }
        do {
            try await service.removeTeamMember(teamId: teamId, uid: uid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Matchs d'équipe

    func setAvailability(match: Match, team: Team, user: AppUser?, available: Bool) async {
        guard let matchId = match.id, let teamId = team.id, let user else { return }
        do {
            try await service.setAvailability(matchId: matchId, teamId: teamId, user: user, available: available)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelTeamMatch(match: Match, team: Team, organizerPseudo: String) async {
        guard let matchId = match.id, let teamId = team.id else { return }
        do {
            try await service.cancelTeamMatch(matchId: matchId, teamId: teamId, organizerPseudo: organizerPseudo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func member(for uid: String) -> AppUser? {
        members.first { $0.id == uid }
    }

    func deleteTeam(team: Team) async {
        guard let teamId = team.id else { return }
        do {
            try await service.deleteTeam(teamId: teamId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
