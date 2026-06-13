import Foundation
import FirebaseFirestore

// Extension feuille de match : chat du match, exclusion, fin de match.
extension FirebaseService {

    // MARK: - Chat du match (matches/{id}/messages)

    func listenMatchMessages(matchId: String, onChange: @escaping ([ChatMessage]) -> Void) -> ListenerRegistration {
        matchesRef.document(matchId).collection("messages")
            .order(by: "sentAt")
            .limit(toLast: 100)
            .addSnapshotListener { snapshot, _ in
                let messages = snapshot?.documents.compactMap { try? $0.data(as: ChatMessage.self) } ?? []
                onChange(messages)
            }
    }

    func sendMatchMessage(matchId: String, sender: AppUser, text: String) async throws {
        guard let uid = sender.id else { return }
        let message = ChatMessage(
            senderId: uid,
            senderPseudo: sender.pseudo,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            sentAt: Date()
        )
        _ = try matchesRef.document(matchId).collection("messages").addDocument(from: message)
    }

    func postMatchSystemMessage(matchId: String, text: String) async throws {
        let message = ChatMessage(senderId: "system", senderPseudo: "Système", text: text, sentAt: Date())
        _ = try matchesRef.document(matchId).collection("messages").addDocument(from: message)
    }

    // MARK: - Écoute du match en temps réel

    func listenMatch(matchId: String, onChange: @escaping (Match?) -> Void) -> ListenerRegistration {
        matchesRef.document(matchId).addSnapshotListener { snapshot, _ in
            onChange(try? snapshot?.data(as: Match.self))
        }
    }

    // MARK: - Choisir sa place sur la feuille

    func setSlot(matchId: String, uid: String, slot: Int) async throws {
        try await matchesRef.document(matchId).updateData([
            "slotAssignments.\(uid)": slot
        ])
    }

    // MARK: - Exclusion d'un participant (organisateur)

    func kickParticipant(matchId: String, uid: String, pseudo: String) async throws {
        try await matchesRef.document(matchId).updateData([
            "participants": FieldValue.arrayRemove([uid])
        ])
        try await postMatchSystemMessage(matchId: matchId, text: "🚫 \(pseudo) a été exclu du match")
    }

    // MARK: - Fin de match (organisateur)

    /// Clôture le match : score final + buteurs, puis distribution des
    /// récompenses à chaque participant selon son côté (A = 1re moitié des
    /// inscrits, B = 2e moitié). XP : +500 participation, +1500 victoire,
    /// +500 par but, +2 skill points par niveau gagné.
    func endMatch(match: Match, scoreA: Int, scoreB: Int, scorers: [String: Int]) async throws {
        guard let matchId = match.id else { return }

        // 1️⃣ Clôturer le match
        try await matchesRef.document(matchId).updateData([
            "status": MatchStatus.played.rawValue,
            "scoreA": scoreA,
            "scoreB": scoreB,
            "scorers": scorers
        ])

        // 2️⃣ Récompenser chaque participant
        let title = "Match \(match.type.displayName) • \(scoreA)-\(scoreB)"
        for uid in match.participants {
            let side = match.side(of: uid) ?? 0
            let myScore = side == 0 ? scoreA : scoreB
            let theirScore = side == 0 ? scoreB : scoreA
            let won = myScore > theirScore
            let drawn = myScore == theirScore
            let goals = scorers[uid] ?? 0

            try await awardMatchResult(uid: uid, won: won, drawn: drawn, goals: goals, title: title)
        }

        // 3️⃣ Annonce dans le chat du match
        try await postMatchSystemMessage(matchId: matchId, text: "🏁 Match terminé : \(scoreA) - \(scoreB)")
    }
}
