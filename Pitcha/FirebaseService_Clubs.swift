import Foundation
import FirebaseFirestore
import FirebaseFunctions

// Extension clubs : rosters fixes (5 titulaires + 3 remplaçants) utilisés
// pour rejoindre un match Classé. Différent du système "Équipes" existant
// (qui reste pour l'organisation libre de matchs Normal).
extension FirebaseService {

    var clubsRef: CollectionReference { db.collection("clubs") }

    /// Crée un club : le créateur en devient capitaine et premier titulaire.
    /// Bloqué si l'utilisateur fait déjà partie de 3 clubs.
    func createClub(name: String, crestIcon: String, crestColorName: String, captain: AppUser) async throws {
        guard let uid = captain.id else { return }
        guard captain.clubIdsValue.count < Club.maxClubsPerUser else {
            throw ClubError.tooManyClubs
        }

        let clubDoc = clubsRef.document()
        let club = Club(
            name: name.trimmingCharacters(in: .whitespaces),
            captainId: uid,
            starterIds: [uid],
            substituteIds: [],
            createdAt: Date(),
            crestIcon: crestIcon,
            crestColorName: crestColorName
        )
        try clubDoc.setData(from: club)
        try await usersRef.document(uid).updateData([
            "clubIds": FieldValue.arrayUnion([clubDoc.documentID])
        ])
    }

    /// Ajoute un joueur (trouvé par pseudo) au roster d'un club, comme
    /// titulaire ou remplaçant. Réservé au capitaine (vérifié côté règles).
    /// Ajoute un AMI (choisi dans la liste, pas un pseudo libre) au roster
    /// d'un club, comme titulaire ou remplaçant. Réservé au capitaine.
    /// Ajoute un ami au roster — passe désormais par la Cloud Function
    /// `addClubMember`, qui vérifie côté serveur que l'appelant est bien
    /// le capitaine avant de toucher au clubIds d'un AUTRE utilisateur.
    /// Le client ne peut plus faire cette écriture croisée lui-même.
    func addToClubRoster(clubId: String, friend: AppUser, asStarter: Bool) async throws {
        guard let uid = friend.id else { throw ClubError.userNotFound }
        let functions = Functions.functions(region: "europe-west1")
        do {
            _ = try await functions.httpsCallable("addClubMember").call([
                "clubId": clubId,
                "targetUid": uid,
                "asStarter": asStarter
            ])
        } catch {
            throw ClubError.serverRejected(message: error.localizedDescription)
        }
    }

    /// Retire un joueur du roster (titulaire ou remplaçant, peu importe où
    /// il est) — capitaine uniquement, ou le joueur lui-même qui quitte.
    /// Retire un joueur du roster — passe par la Cloud Function
    /// `removeClubMember` (touche le clubIds d'un AUTRE utilisateur).
    func removeFromClubRoster(clubId: String, uid: String) async throws {
        let functions = Functions.functions(region: "europe-west1")
        do {
            _ = try await functions.httpsCallable("removeClubMember").call([
                "clubId": clubId,
                "targetUid": uid
            ])
        } catch {
            throw ClubError.serverRejected(message: error.localizedDescription)
        }
    }

    /// Fait passer un remplaçant titulaire (si une place est libre) ou
    /// inversement — passe par la Cloud Function `moveClubRosterSlot`
    /// pour rester cohérent avec les deux autres actions de capitaine.
    func moveClubRosterSlot(clubId: String, uid: String, toStarter: Bool) async throws {
        let functions = Functions.functions(region: "europe-west1")
        do {
            _ = try await functions.httpsCallable("moveClubRosterSlot").call([
                "clubId": clubId,
                "targetUid": uid,
                "toStarter": toStarter
            ])
        } catch {
            throw ClubError.serverRejected(message: error.localizedDescription)
        }
    }

    /// Un membre (pas le capitaine) se retire lui-même du club.
    func leaveClub(clubId: String) async throws {
        let functions = Functions.functions(region: "europe-west1")
        do {
            _ = try await functions.httpsCallable("leaveClub").call(["clubId": clubId])
        } catch {
            throw ClubError.serverRejected(message: error.localizedDescription)
        }
    }

    /// Rejoint un match Classé EN CLUB : les 5 titulaires rejoignent d'un
    /// coup (plus de choix de slot individuel). Réservé au capitaine, coût
    /// symbolique de 1 coin (comme un join individuel classique) prélevé
    /// sur le capitaine qui engage son club.
    func joinRankedMatchWithClub(matchId: String, club: Club, captainUid: String) async throws {
        guard club.captainId == captainUid else { throw ClubError.notCaptain }
        guard club.isReadyForRanked else { throw ClubError.clubNotReady }

        // ⚠️ TEMP TEST — même plafond que createRanked, pour rester cohérent
        // avec le maxPlayers réduit pendant les tests à 2 appareils.
        let testParticipants = Array(club.starterIds.prefix(Club.minStartersForRanked))

        let matchDoc = matchesRef.document(matchId)
        let userDoc = usersRef.document(captainUid)

        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let matchSnap = try transaction.getDocument(matchDoc)
                let userSnap = try transaction.getDocument(userDoc)
                guard let match = try? matchSnap.data(as: Match.self),
                      let user = try? userSnap.data(as: AppUser.self) else {
                    throw PitchaError.dataCorrupted
                }
                guard match.isRankedMatch else { throw PitchaError.dataCorrupted }
                guard !match.isFull else { throw PitchaError.matchFull }
                // Aucun titulaire du club déjà présent (évite un doublon ou
                // un club qui se retrouverait face à lui-même).
                guard testParticipants.allSatisfy({ !match.participants.contains($0) }) else {
                    throw ClubError.alreadyInMatch
                }
                guard user.coins >= 1 else { throw PitchaError.notEnoughCoins }

                transaction.updateData([
                    "participants": FieldValue.arrayUnion(testParticipants)
                ], forDocument: matchDoc)
                transaction.updateData([
                    "coins": FieldValue.increment(Int64(-1))
                ], forDocument: userDoc)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    /// Dissout un club — passe par la Cloud Function `dissolveClub`, qui
    /// nettoie le clubIds de TOUS les membres de façon fiable (l'ancienne
    /// version ici utilisait un `try?` qui échouait silencieusement pour
    /// les membres autres que l'appelant, laissant des clubIds fantômes).
    func deleteClub(clubId: String) async throws {
        let functions = Functions.functions(region: "europe-west1")
        do {
            _ = try await functions.httpsCallable("dissolveClub").call(["clubId": clubId])
        } catch {
            throw ClubError.serverRejected(message: error.localizedDescription)
        }
    }

    func fetchMyClubs(clubIds: [String]) async throws -> [Club] {
        guard !clubIds.isEmpty else { return [] }
        var results: [Club] = []
        for chunk in stride(from: 0, to: clubIds.count, by: 10).map({ Array(clubIds[$0..<min($0+10, clubIds.count)]) }) {
            let snapshot = try await clubsRef
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            results.append(contentsOf: snapshot.documents.compactMap { try? $0.data(as: Club.self) })
        }
        return results
    }

    func listenClub(clubId: String, onChange: @escaping (Club?) -> Void) -> ListenerRegistration {
        clubsRef.document(clubId).addSnapshotListener { snapshot, _ in
            onChange(try? snapshot?.data(as: Club.self))
        }
    }
}

enum ClubError: LocalizedError {
    case tooManyClubs
    case targetTooManyClubs(pseudo: String)
    case userNotFound
    case alreadyInRoster(pseudo: String)
    case rosterFull
    case clubNotReady
    case notCaptain
    case alreadyInMatch
    case serverRejected(message: String)

    var errorDescription: String? {
        switch self {
        case .tooManyClubs: return "Tu fais déjà partie de 3 clubs, le maximum autorisé."
        case .targetTooManyClubs(let pseudo): return "\(pseudo) fait déjà partie de 3 clubs."
        case .userNotFound: return "Aucun joueur trouvé avec ce pseudo."
        case .alreadyInRoster(let pseudo): return "\(pseudo) est déjà dans ce club."
        case .rosterFull: return "Ce roster est déjà complet."
        case .clubNotReady: return "Il manque des titulaires à ce club pour jouer un match Classé (5 requis)."
        case .notCaptain: return "Seul le capitaine du club peut faire cette action."
        case .alreadyInMatch: return "Un joueur de ce club est déjà dans ce match."
        case .serverRejected(let message): return message
        }
    }
}
