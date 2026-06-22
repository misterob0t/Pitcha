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

    func signUp(email: String, password: String, pseudo: String, gender: Gender) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        try await result.user.sendEmailVerification()
        var user = AppUser.new(uid: result.user.uid, pseudo: pseudo, email: email)
        // Champ minuscule pour permettre la recherche par pseudo insensible à la casse
        user.pseudoLower = pseudo.trimmingCharacters(in: .whitespaces).lowercased()
        // Sexe choisi à l'inscription : non modifiable ensuite (pas d'écran d'édition)
        user.gender = gender.rawValue
        try usersRef.document(result.user.uid).setData(from: user)
    }

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
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

    func listenUser(uid: String, onChange: @escaping (AppUser?) -> Void) -> ListenerRegistration {
        usersRef.document(uid).addSnapshotListener { snapshot, _ in
            onChange(try? snapshot?.data(as: AppUser.self))
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
    func listenOpenMatches(onChange: @escaping ([Match]) -> Void) -> ListenerRegistration {
        let since = Date().addingTimeInterval(-24 * 3600)
        return matchesRef
            .whereField("date", isGreaterThan: since)
            .order(by: "date")
            .addSnapshotListener { snapshot, _ in
                let now = Date()
                let matches = (snapshot?.documents.compactMap { try? $0.data(as: Match.self) } ?? [])
                    .filter { match in
                        switch match.status {
                        case .open:
                            return true
                        case .pendingValidation:
                            return true
                        case .played, .contested:
                            let finishedAt = match.scoreSubmittedAt ?? match.date
                            return now.timeIntervalSince(finishedAt) < 24 * 3600
                        case .cancelled:
                            return false
                        }
                    }
                onChange(matches)
            }
    }

    func createMatch(_ match: Match) async throws {
        _ = try matchesRef.addDocument(from: match)
    }

    /// Rejoindre un match : déduit 1 coin (non remboursable), ajoute le joueur.
    /// Transaction atomique pour éviter les états incohérents.
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
                guard user.coins >= 1 else { throw PitchaError.notEnoughCoins }

                transaction.updateData(["participants": FieldValue.arrayUnion([uid])], forDocument: matchDoc)
                transaction.updateData(["coins": FieldValue.increment(Int64(-1))], forDocument: userDoc)
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
