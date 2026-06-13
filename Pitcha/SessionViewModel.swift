import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class SessionViewModel: ObservableObject {

    enum AuthState {
        case loading
        case loggedOut
        case emailNotVerified
        case loggedIn
    }

    @Published var state: AuthState = .loading
    @Published var user: AppUser?
    @Published var errorMessage: String?
    @Published var isWorking = false

    private let service = FirebaseService.shared
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var userListener: ListenerRegistration?
    private var presenceTask: Task<Void, Never>?

    init() {
        listenAuthState()
    }

    deinit {
        if let authHandle { Auth.auth().removeStateDidChangeListener(authHandle) }
        userListener?.remove()
        presenceTask?.cancel()
    }

    // MARK: - Auth state

    private func listenAuthState() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            guard let self else { return }
            Task { @MainActor in
                guard let firebaseUser else {
                    self.detachUserListener()
                    self.stopPresence()
                    self.user = nil
                    self.state = .loggedOut
                    return
                }
                if firebaseUser.isEmailVerified {
                    self.attachUserListener(uid: firebaseUser.uid)
                    self.startPresence(uid: firebaseUser.uid)
                    self.state = .loggedIn
                } else {
                    self.state = .emailNotVerified
                }
            }
        }
    }

    private func attachUserListener(uid: String) {
        userListener?.remove()
        userListener = service.listenUser(uid: uid) { [weak self] user in
            Task { @MainActor in self?.user = user }
        }
    }

    private func detachUserListener() {
        userListener?.remove()
        userListener = nil
    }

    // MARK: - Présence (statut en ligne)

    /// Met à jour lastSeen toutes les 60s tant que l'app tourne.
    /// Un ami est "en ligne" si son lastSeen date de moins de 2 minutes.
    private func startPresence(uid: String) {
        presenceTask?.cancel()
        presenceTask = Task { [service] in
            while !Task.isCancelled {
                await service.updatePresence(uid: uid)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func stopPresence() {
        presenceTask?.cancel()
        presenceTask = nil
    }

    // MARK: - Actions

    func signUp(email: String, password: String, pseudo: String) async {
        await run {
            try await self.service.signUp(email: email, password: password, pseudo: pseudo)
        }
    }

    func signIn(email: String, password: String) async {
        await run {
            try await self.service.signIn(email: email, password: password)
        }
    }

    func signOut() {
        do {
            stopPresence()
            try service.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resendVerificationEmail() async {
        await run {
            try await self.service.resendVerificationEmail()
        }
    }

    /// À appeler depuis l'écran "Vérifie ton email" via un bouton "J'ai vérifié".
    func checkEmailVerified() async {
        await run {
            let verified = try await self.service.reloadCurrentUser()
            if verified, let uid = self.service.currentUID {
                self.attachUserListener(uid: uid)
                self.startPresence(uid: uid)
                self.state = .loggedIn
            } else {
                self.errorMessage = "Email pas encore vérifié. Regarde ta boîte mail (et les spams)."
            }
        }
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
