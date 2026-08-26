import Foundation
import FirebaseFirestore

// Extension feuille de match : chat, exclusion, votes, fin de match.
extension FirebaseService {

    // MARK: - Chat du match

    func listenMatchMessages(matchId: String, onChange: @escaping ([ChatMessage]) -> Void) -> ListenerRegistration {
        matchesRef.document(matchId).collection("messages")
            .order(by: "sentAt").limit(toLast: 100)
            .addSnapshotListener { snapshot, _ in
                let messages = snapshot?.documents.compactMap { try? $0.data(as: ChatMessage.self) } ?? []
                onChange(messages)
            }
    }

    func sendMatchMessage(matchId: String, sender: AppUser, text: String) async throws {
        guard let uid = sender.id else { return }
        let message = ChatMessage(senderId: uid, senderPseudo: sender.pseudo,
                                  text: text.trimmingCharacters(in: .whitespacesAndNewlines), sentAt: nil)
        _ = try matchesRef.document(matchId).collection("messages").addDocument(from: message)
    }

    func postMatchSystemMessage(matchId: String, text: String) async throws {
        let message = ChatMessage(senderId: "system", senderPseudo: "Système", text: text, sentAt: nil)
        _ = try matchesRef.document(matchId).collection("messages").addDocument(from: message)
    }

    // MARK: - Écoute du match en temps réel

    func listenMatch(matchId: String, onChange: @escaping (Match?) -> Void) -> ListenerRegistration {
        matchesRef.document(matchId).addSnapshotListener { snapshot, _ in
            onChange(try? snapshot?.data(as: Match.self))
        }
    }

    // MARK: - Écoute des votes en temps réel

    func listenVotes(matchId: String, onChange: @escaping ([String: String]) -> Void) -> ListenerRegistration {
        matchesRef.document(matchId).collection("votes")
            .addSnapshotListener { snapshot, _ in
                var votes: [String: String] = [:]
                snapshot?.documents.forEach { doc in
                    votes[doc.documentID] = doc.data()["vote"] as? String
                }
                onChange(votes)
            }
    }

    // MARK: - Vote MVP (un vote par participant, peut changer d'avis)

    func listenMvpVotes(matchId: String, onChange: @escaping ([String: String]) -> Void) -> ListenerRegistration {
        matchesRef.document(matchId).collection("mvpVotes")
            .addSnapshotListener { snapshot, _ in
                var votes: [String: String] = [:]   // voterUid -> votedForUid
                snapshot?.documents.forEach { doc in
                    votes[doc.documentID] = doc.data()["votedFor"] as? String
                }
                onChange(votes)
            }
    }

    func voteMvp(matchId: String, voterUid: String, votedForUid: String) async throws {
        try await matchesRef.document(matchId).collection("mvpVotes").document(voterUid).setData([
            "votedFor": votedForUid,
            "timestamp": Timestamp(date: Date())
        ])
    }

    // MARK: - Choisir sa place sur la feuille

    func setSlot(matchId: String, uid: String, slot: Int) async throws {
        try await matchesRef.document(matchId).updateData(["slotAssignments.\(uid)": slot])
    }

    // MARK: - Exclusion d'un participant (organisateur)

    func kickParticipant(matchId: String, uid: String, pseudo: String) async throws {
        try await matchesRef.document(matchId).updateData([
            "participants": FieldValue.arrayRemove([uid])
        ])
    }

    // MARK: - Soumettre le score (→ pendingValidation)

    /// L'organisateur soumet score + buteurs. Le match passe en "pendingValidation"
    /// et les participants peuvent voter pour valider ou contester.
    func submitMatchResult(match: Match, scoreA: Int, scoreB: Int, scorers: [String: Int]) async throws {
        guard let matchId = match.id else { return }
        let now = Date()
        // Passer en pendingValidation : les participants votent pour valider
        try await matchesRef.document(matchId).updateData([
            "status": MatchStatus.pendingValidation.rawValue,
            "scoreA": scoreA,
            "scoreB": scoreB,
            "scorers": scorers,
            "scoreSubmittedAt": Timestamp(date: now)
        ])
        try await postMatchSystemMessage(matchId: matchId, text: "⏳ Score soumis : \(scoreA) – \(scoreB). Votez pour valider !")
        await MainActor.run {
            BackgroundTaskService.shared.scheduleMatchTimeoutCheck(submittedAt: now)
        }
    }

    // MARK: - Voter (participant)

    func voteMatch(matchId: String, uid: String, validate: Bool) async throws {
        let voteValue = validate ? "validate" : "contest"
        try await matchesRef.document(matchId).collection("votes").document(uid).setData([
            "vote": voteValue,
            "timestamp": Timestamp(date: Date())
        ])
        // La vérification du seuil et la distribution XP/PL sont désormais
        // gérées côté serveur (Cloud Function onVoteWritten), déclenchée
        // automatiquement par cette écriture. Le client ne fait QUE voter —
        // il n'a plus les droits d'écriture pour distribuer quoi que ce soit
        // lui-même (voir les règles Firestore resserrées).
    }

    // MARK: - Annulation

    func cancelMatch(matchId: String) async throws {
        try await matchesRef.document(matchId).updateData(["status": MatchStatus.cancelled.rawValue])
    }
}
