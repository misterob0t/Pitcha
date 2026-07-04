import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Couche données unique. Toutes les lectures/écritures Firestore passent ici.
/// Aucune vue ni aucun ViewModel ne doit appeler Firestore directement.
final class FirebaseService {
    static let shared = FirebaseService()
    private init() {}

    let db = Firestore.firestore()

    var currentUID: String? { Auth.auth().currentUser?.uid }

    // MARK: - Collections

    var usersRef: CollectionReference { db.collection("users") }
    var matchesRef: CollectionReference { db.collection("matches") }
    var teamsRef: CollectionReference { db.collection("teams") }

    // MARK: - Auth

    func signUp(email: String, password: String, pseudo: String, gender: Gender, city: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        try await result.user.sendEmailVerification()
        var user = AppUser.new(uid: result.user.uid, pseudo: pseudo, email: email, city: city)
        // Champ minuscule pour permettre la recherche par pseudo insensible à la casse
        user.pseudoLower = pseudo.trimmingCharacters(in: .whitespaces).lowercased()
        // Sexe choisi à l'inscription : non modifiable ensuite (pas d'écran d'édition)
        user.gender = gender.rawValue
        // Session active dès l'inscription : cet appareil est "l'appareil
        // connecté" par défaut. Stockage local AVANT l'écriture Firestore
        // pour ne jamais se déconnecter soi-même par une fausse alerte de
        // course (le listener local ne peut pas se déclencher avant que la
        // valeur locale soit déjà en place, ces lignes étant synchrones).
        let sessionId = UUID().uuidString
        UserDefaults.standard.set(sessionId, forKey: "pitcha.sessionId.\(result.user.uid)")
        user.activeSessionId = sessionId
        // @DocumentID doit rester nil à l'écriture : Firestore le déduit lui-même
        // du chemin du document (.document(result.user.uid)) et log un warning
        // sinon ("Attempting to initialize or set a @DocumentID property...").
        user.id = nil
        try usersRef.document(result.user.uid).setData(from: user)
    }

    /// Connecte l'utilisateur ET invalide toute session active sur un autre
    /// appareil (comportement "un seul appareil à la fois", façon Snapchat) :
    /// une nouvelle sessionId est écrite sur le document, et chaque appareil
    /// connecté écoute ce champ pour se déconnecter tout seul s'il change.
    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        let sessionId = UUID().uuidString
        // Stockage local AVANT l'écriture Firestore, voir commentaire signUp().
        UserDefaults.standard.set(sessionId, forKey: "pitcha.sessionId.\(result.user.uid)")
        try await usersRef.document(result.user.uid).updateData(["activeSessionId": sessionId])
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    /// Écoute les matchs PRIVÉS organisés par des amis (un seul whereField
    /// "isPrivate" = aucun index composite requis ; le filtre par ami et le
    /// statut se font côté client).
    func listenFriendsPrivateMatches(friendIds: [String], onChange: @escaping ([Match]) -> Void) -> ListenerRegistration {
        matchesRef
            .whereField("isPrivate", isEqualTo: true)
            .addSnapshotListener { snapshot, _ in
                let friendSet = Set(friendIds)
                let matches = (snapshot?.documents.compactMap { try? $0.data(as: Match.self) } ?? [])
                    .filter { friendSet.contains($0.organizerId) && $0.status == .open && $0.date > Date() }
                    .sorted { $0.date < $1.date }
                onChange(matches)
            }
    }

    /// Masque un match clôturé (joué/contesté) de la liste de l'utilisateur.
    /// Purement côté préférence perso : n'affecte ni le match ni les autres.
    func dismissMatch(uid: String, matchId: String) async throws {
        try await usersRef.document(uid).updateData([
            "dismissedMatches": FieldValue.arrayUnion([matchId])
        ])
    }

    func resendVerificationEmail() async throws {
        try await Auth.auth().currentUser?.sendEmailVerification()
    }

    func reloadCurrentUser() async throws -> Bool {
        try await Auth.auth().currentUser?.reload()
        return Auth.auth().currentUser?.isEmailVerified ?? false
    }

    // MARK: - User

    /// Écoute le document utilisateur. Expose aussi si le snapshot vient du
    /// cache local (isFromCache) : nécessaire pour ne pas comparer une donnée
    /// potentiellement obsolète lors de la vérification de session active
    /// (voir SessionViewModel.attachUserListener).
    func listenUser(uid: String, onChange: @escaping (AppUser?, Bool) -> Void) -> ListenerRegistration {
        usersRef.document(uid).addSnapshotListener { snapshot, _ in
            let isFromCache = snapshot?.metadata.isFromCache ?? true
            onChange(try? snapshot?.data(as: AppUser.self), isFromCache)
        }
    }

    func updateUser(uid: String, fields: [String: Any]) async throws {
        try await usersRef.document(uid).updateData(fields)
    }

    func saveAttributes(uid: String, attributes: PlayerAttributes, skillPoints: Int) async throws {
        // Sauvegarde sur le document principal — JAMAIS en sous-collection
        try await usersRef.document(uid).updateData([
            "attributes": [
                "vit": attributes.vit,
                "tir": attributes.tir,
                "pas": attributes.pas,
                "dri": attributes.dri,
                "def": attributes.def,
                "phy": attributes.phy
            ],
            "skillPoints": skillPoints
        ])
    }

    // MARK: - Matchs

    /// Matchs visibles dans la liste. Fenêtre large (24h dans le passé,
    /// illimité dans le futur) + filtrage fin côté client pour que :
    /// - les matchs "open" à venir restent visibles
    /// - les matchs "pendingValidation" restent visibles MÊME si leur heure
    ///   de début est passée (le vote doit pouvoir continuer)
    /// - les matchs "played"/"contested" restent visibles 24h après la
    ///   soumission du score, pour que les joueurs voient le résultat final
    ///   et le taux de validation avant qu'ils ne disparaissent
    /// ⚠️ Listener temps réel sur une requête LARGE (toute la liste de
    /// matchs). À chaque écriture sur N'IMPORTE QUEL document correspondant
    /// (n'importe qui, n'importe où, qui crée/rejoint un match), Firestore
    /// re-livre jusqu'à 200 documents à TOUS les clients qui écoutent cette
    /// requête simultanément. Le coût grossit en (DAU_à_l'écran × fréquence
    /// d'écriture globale), pas juste en DAU — c'est le seul vrai risque de
    /// croissance non-linéaire qui restait dans l'app. Conservé pour
    /// compat, mais NE PLUS L'UTILISER pour la liste principale (voir
    /// fetchOpenMatches ci-dessous, utilisé à la place dans MatchsView).
    @available(*, deprecated, message: "Utiliser fetchOpenMatches() + rafraîchissement périodique pour la liste principale — ce listener fan-out coûte cher à l'échelle")
    func listenOpenMatches(onChange: @escaping ([Match]) -> Void) -> ListenerRegistration {
        let since = Date().addingTimeInterval(-24 * 3600)
        return matchesRef
            .whereField("date", isGreaterThan: since)
            .order(by: "date")
            .limit(to: 200)
            .addSnapshotListener { snapshot, _ in
                onChange(Self.filterVisibleMatches(snapshot))
            }
    }

    /// Lecture ponctuelle (pas de listener) : coût FIXE par appel, jamais
    /// multiplié par l'activité des autres utilisateurs. Pensé pour être
    /// rappelé périodiquement (toutes les 20-30s) UNIQUEMENT pendant que
    /// l'écran Matchs est réellement visible — c'est ce qu'utilise
    /// MatchsViewModel. La fraîcheur perçue reste excellente (quelques
    /// secondes de délai max) pour un coût borné et prévisible.
    func fetchOpenMatches() async throws -> [Match] {
        let since = Date().addingTimeInterval(-24 * 3600)
        let snapshot = try await matchesRef
            .whereField("date", isGreaterThan: since)
            .order(by: "date")
            .limit(to: 200)
            .getDocuments()
        return Self.filterVisibleMatches(snapshot)
    }

    private static func filterVisibleMatches(_ snapshot: QuerySnapshot?) -> [Match] {
        let now = Date()
        return (snapshot?.documents.compactMap { try? $0.data(as: Match.self) } ?? [])
            .filter { match in
                switch match.status {
                case .open, .pendingValidation:
                    return true
                case .played, .contested:
                    let finishedAt = match.scoreSubmittedAt ?? match.date
                    return now.timeIntervalSince(finishedAt) < 24 * 3600
                case .cancelled:
                    return false
                }
            }
    }

    func createMatch(_ match: Match) async throws {
        _ = try matchesRef.addDocument(from: match)
    }

    /// Rejoindre un match : déduit 1 coin (non remboursable) pour les freemium,
    /// GRATUIT pour les abonnés Premium. Transaction atomique.
    func joinMatch(matchId: String, uid: String) async throws {
        let matchDoc = matchesRef.document(matchId)
        let userDoc = usersRef.document(uid)

        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let matchSnap = try transaction.getDocument(matchDoc)
                let userSnap = try transaction.getDocument(userDoc)

                guard let match = try? matchSnap.data(as: Match.self),
                      let user = try? userSnap.data(as: AppUser.self) else {
                    throw PitchaError.dataCorrupted
                }
                guard !match.isFull else { throw PitchaError.matchFull }
                guard !match.participants.contains(uid) else { throw PitchaError.alreadyJoined }

                transaction.updateData(["participants": FieldValue.arrayUnion([uid])], forDocument: matchDoc)

                // Les membres Premium ne paient pas de coin pour rejoindre un match
                if !user.hasPremium {
                    guard user.coins >= 1 else { throw PitchaError.notEnoughCoins }
                    transaction.updateData(["coins": FieldValue.increment(Int64(-1))], forDocument: userDoc)
                }
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    /// Quitter un match : retire le joueur. Le coin n'est PAS remboursé.
    func leaveMatch(matchId: String, uid: String) async throws {
        try await matchesRef.document(matchId).updateData([
            "participants": FieldValue.arrayRemove([uid])
        ])
    }

    // MARK: - Équipes

    func listenTeams(forUser uid: String, onChange: @escaping ([Team]) -> Void) -> ListenerRegistration {
        teamsRef
            .whereField("memberIds", arrayContains: uid)
            .addSnapshotListener { snapshot, _ in
                let teams = snapshot?.documents.compactMap { try? $0.data(as: Team.self) } ?? []
                onChange(teams)
            }
    }

    func createTeam(name: String, ownerId: String) async throws {
        let team = Team(name: name, ownerId: ownerId, memberIds: [ownerId], createdAt: Date())
        _ = try teamsRef.addDocument(from: team)
    }
}

// MARK: - Erreurs métier

enum PitchaError: LocalizedError {
    case matchFull
    case alreadyJoined
    case notEnoughCoins
    case dataCorrupted

    var errorDescription: String? {
        switch self {
        case .matchFull: return "Ce match est complet."
        case .alreadyJoined: return "Tu participes déjà à ce match."
        case .notEnoughCoins: return "Pas assez de coins (1 coin requis)."
        case .dataCorrupted: return "Données invalides, réessaie."
        }
    }
}
