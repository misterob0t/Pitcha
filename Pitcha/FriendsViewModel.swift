import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class FriendsViewModel: ObservableObject {

    @Published var friends: [AppUser] = []
    @Published var requests: [AppUser] = []        // demandes reçues (profils)
    @Published var requestSent = false
    @Published var searchResult: AppUser?
    @Published var searchMessage: String?
    @Published var errorMessage: String?
    @Published var isWorking = false

    private let service = FirebaseService.shared
    private var listeners: [ListenerRegistration] = []

    deinit {
        listeners.forEach { $0.remove() }
    }

    /// Écoute les profils amis en temps réel (statut online vivant).
    /// À rappeler quand la liste d'uids change (le doc user est déjà live).
    func listen(friendUids: [String]) {
        listeners.forEach { $0.remove() }
        listeners = service.listenUsers(uids: friendUids) { [weak self] users in
            Task { @MainActor in
                // Online d'abord, puis alphabétique
                self?.friends = users.sorted {
                    ($0.isOnline ? 0 : 1, $0.pseudo.lowercased()) < ($1.isOnline ? 0 : 1, $1.pseudo.lowercased())
                }
            }
        }
    }

    /// Charge les profils des demandes reçues.
    func loadRequests(uids: [String]) async {
        do {
            let users = try await service.fetchUsers(uids: uids)
            requests = uids.compactMap { uid in users.first { $0.id == uid } }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Recherche par pseudo

    func search(pseudo: String, myUid: String?, currentFriends: [String]) async {
        let clean = pseudo.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        isWorking = true
        searchResult = nil
        searchMessage = nil
        do {
            guard let user = try await service.findUser(pseudo: clean) else {
                searchMessage = "Aucun joueur trouvé avec ce pseudo."
                isWorking = false
                return
            }
            if user.id == myUid {
                searchMessage = "C'est toi 😄"
            } else if let uid = user.id, currentFriends.contains(uid) {
                searchMessage = "\(user.pseudo) est déjà ton ami."
            } else if let myUid, user.incomingRequests.contains(myUid) {
                searchMessage = "Demande déjà envoyée à \(user.pseudo), en attente de sa réponse."
            } else {
                searchResult = user
            }
        } catch {
            searchMessage = error.localizedDescription
        }
        isWorking = false
    }

    // MARK: - Demandes / suppression

    /// Envoie une demande d'ami (l'autre devra accepter).
    func sendRequest(to friend: AppUser, myUid: String?) async {
        guard let myUid, let friendUid = friend.id else { return }
        isWorking = true
        do {
            try await service.sendFriendRequest(myUid: myUid, to: friendUid)
            requestSent = true
            searchMessage = "Demande envoyée à \(friend.pseudo) ✓"
            searchResult = nil
        } catch {
            searchMessage = error.localizedDescription
        }
        isWorking = false
    }

    func accept(_ requester: AppUser, myUid: String?) async {
        guard let myUid, let requesterUid = requester.id else { return }
        do {
            try await service.acceptFriendRequest(myUid: myUid, from: requesterUid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func decline(_ requester: AppUser, myUid: String?) async {
        guard let myUid, let requesterUid = requester.id else { return }
        do {
            try await service.declineFriendRequest(myUid: myUid, from: requesterUid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeFriend(_ friend: AppUser, myUid: String?) async {
        guard let myUid, let friendUid = friend.id else { return }
        do {
            try await service.removeFriend(myUid: myUid, friendUid: friendUid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
