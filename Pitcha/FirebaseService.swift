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

    func signUp(email: String, password: String, pseudo: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        try await result.user.sendEmailVerification()
        let user = AppUser.new(uid: result.user.uid, pseudo: pseudo, email: email)
        try usersRef.document(result.user.uid).setData(from: user)
    }

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signOut() throws {
        try Auth.auth().signOut()
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

    /// Matchs ouverts à venir. Une seule inégalité (date) + tri sur ce même
    /// champ = AUCUN index composite requis ; le statut est filtré côté client.
    func listenOpenMatches(onChange: @escaping ([Match]) -> Void) -> ListenerRegistration {
        matchesRef
            .whereField("date", isGreaterThan: Date())
            .order(by: "date")
            .addSnapshotListener { snapshot, _ in
                let matches = (snapshot?.documents.compactMap { try? $0.data(as: Match.self) } ?? [])
                    .filter { $0.status == .open }
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

    func cancelMatch(matchId: String) async throws {
        try await matchesRef.document(matchId).updateData([
            "status": MatchStatus.cancelled.rawValue
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
