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

    /// true juste après une inscription réussie : déclenche le message de
    /// bienvenue "20 coins offerts" à la toute première arrivée sur
    /// l'app (une seule fois par compte, jamais aux connexions suivantes).
    @Published var showWelcomeBonus = false

    /// Renseigné quand cet appareil est déconnecté automatiquement parce
    /// qu'une connexion plus récente a eu lieu sur un autre appareil.
    /// Affiché sous forme d'alerte par AuthView.
    @Published var forcedLogoutMessage: String? = nil

    /// Invitations à rejoindre un match reçues d'amis (affichées via la cloche).
    @Published var pendingMatchInvites: [MatchInvite] = []

    private let service = FirebaseService.shared
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var userListener: ListenerRegistration?
    private var matchInvitesListener: ListenerRegistration?

    init() {
        listenAuthState()
    }

    deinit {
        if let authHandle { Auth.auth().removeStateDidChangeListener(authHandle) }
        userListener?.remove()
        matchInvitesListener?.remove()
        // deinit n'est pas isolé au MainActor : on bascule explicitement
        // dans une Task @MainActor pour appeler le service de présence
        // sans bloquer ni violer l'isolation d'acteur.
        Task { @MainActor in
            PresenceService.shared.stop()
        }
    }

    // MARK: - Auth state

    private func listenAuthState() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            guard let self else { return }
            Task { @MainActor in
                guard let firebaseUser else {
                    self.detachUserListener()
                    self.detachMatchInvitesListener()
                    self.stopPresence()
                    self.user = nil
                    self.state = .loggedOut
                    return
                }
                if firebaseUser.isEmailVerified {
                    self.attachUserListener(uid: firebaseUser.uid)
                    self.attachMatchInvitesListener(uid: firebaseUser.uid)
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
        userListener = service.listenUser(uid: uid) { [weak self] fetchedUser, isFromCache in
            Task { @MainActor in
                guard let self else { return }

                // Vérification "une seule session à la fois" (façon Snapchat) :
                // UNIQUEMENT sur un snapshot confirmé par le serveur. Le tout
                // premier snapshot reçu après une connexion vient souvent du
                // cache local et reflète encore l'ANCIENNE session (avant notre
                // propre écriture) — le comparer aurait fait se déconnecter
                // l'appareil qui vient tout juste de se connecter, même seul.
                if !isFromCache, let fetchedUser {
                    let sessionKey = "pitcha.sessionId.\(uid)"
                    if let remoteSession = fetchedUser.activeSessionId {
                        if let mySession = UserDefaults.standard.string(forKey: sessionKey) {
                            if mySession != remoteSession {
                                self.forcedLogoutMessage = "Tu as été déconnecté car ton compte a été utilisé sur un autre appareil."
                                self.signOut()
                                return
                            }
                        } else {
                            // Aucune session locale connue pour ce compte sur cet
                            // appareil (ex: tout premier lancement après un signUp
                            // très récent) : on adopte celle du serveur sans se
                            // déconnecter soi-même par erreur.
                            UserDefaults.standard.set(remoteSession, forKey: sessionKey)
                        }
                    }
                }

                self.user = fetchedUser
            }
        }
        // Backfill ponctuel : si le compte a été créé avant l'ajout du champ
        // pseudoLower, on le renseigne automatiquement à la connexion pour
        // que la recherche d'amis le trouve immédiatement.
        Task { await self.service.backfillPseudoLowerIfNeeded(uid: uid) }
    }

    private func detachUserListener() {
        userListener?.remove()
        userListener = nil
    }

    // MARK: - Invitations à un match (notif locale sur nouvelle invitation uniquement)

    private func attachMatchInvitesListener(uid: String) {
        matchInvitesListener?.remove()
        matchInvitesListener = service.listenMatchInvites(uid: uid) { [weak self] invites, hasNewInvite in
            Task { @MainActor in
                guard let self else { return }
                self.pendingMatchInvites = invites
                if hasNewInvite, let latest = invites.first {
                    NotificationService.showLocal(
                        title: "Invitation à un match",
                        body: "\(latest.invitedByPseudo) t'invite à rejoindre son match."
                    )
                }
            }
        }
    }

    private func detachMatchInvitesListener() {
        matchInvitesListener?.remove()
        matchInvitesListener = nil
    }

    // MARK: - Présence (statut en ligne)

    /// Présence via Realtime Database : écriture uniquement au connect/
    /// disconnect réel (géré côté serveur Firebase), zéro polling Firestore.
    /// Voir PresenceService.swift pour le détail de l'architecture.
    private func startPresence(uid: String) {
        PresenceService.shared.start(uid: uid)
    }

    private func stopPresence() {
        PresenceService.shared.stop()
    }

    // MARK: - Actions

    // MARK: - Actions email/password

    func signUp(email: String, password: String, pseudo: String, gender: Gender, city: String, position: PlayerPosition) async {
        await run {
            try await self.service.signUp(email: email, password: password, pseudo: pseudo, gender: gender, city: city, position: position)
        }
        // Uniquement si l'inscription a réussi (pas d'erreur en attente)
        if errorMessage == nil {
            showWelcomeBonus = true
        }
    }

    func signIn(email: String, password: String) async {
        await run {
            try await self.service.signIn(email: email, password: password)
        }
    }

    func resendVerificationEmail() async {
        await run {
            try await self.service.resendVerificationEmail()
        }
    }

    func refreshVerification() async {
        await run {
            try await Auth.auth().currentUser?.reload()
            if Auth.auth().currentUser?.isEmailVerified == true {
                if let uid = Auth.auth().currentUser?.uid {
                    self.attachUserListener(uid: uid)
                    self.startPresence(uid: uid)
                }
                self.state = .loggedIn
            }
        }
    }

    func sendPasswordReset(email: String) async {
        await run {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        }
    }

    // MARK: - Suppression de compte

    @Published var deletionError: String?

    func deleteAccount(password: String) async -> Bool {
        deletionError = nil
        do {
            stopPresence()
            try await service.deleteAccount(password: password)
            return true
        } catch {
            deletionError = error.localizedDescription
            return false
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
