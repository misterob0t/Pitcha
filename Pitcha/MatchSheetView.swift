import SwiftUI
import Combine
import FirebaseFirestore

// MARK: - ViewModel

@MainActor
final class MatchSheetViewModel: ObservableObject {
    @Published var match: Match?
    @Published var players: [String: AppUser] = [:]
    @Published var messages: [ChatMessage] = []
    @Published var votes: [String: String] = [:]   // uid -> "validate"|"contest"
    @Published var mvpVotes: [String: String] = [:] // voterUid -> votedForUid
    @Published var errorMessage: String?
    @Published var isWorking = false

    private let service = FirebaseService.shared
    private var matchListener: ListenerRegistration?
    private var messagesListener: ListenerRegistration?
    private var votesListener: ListenerRegistration?
    private var mvpVotesListener: ListenerRegistration?

    deinit { matchListener?.remove(); messagesListener?.remove(); votesListener?.remove(); mvpVotesListener?.remove() }

    func listen(matchId: String) {
        matchListener?.remove()
        matchListener = service.listenMatch(matchId: matchId) { [weak self] match in
            Task { @MainActor in
                self?.match = match
                if let uids = match?.participants { await self?.loadPlayers(uids: uids) }
                // Le timeout 48h est désormais géré par une Cloud Function
                // planifiée côté serveur (finalizeStaleMatches) — le client
                // n'a plus les droits pour distribuer XP/PL lui-même.
            }
        }
        messagesListener?.remove()
        messagesListener = service.listenMatchMessages(matchId: matchId) { [weak self] msgs in
            Task { @MainActor in self?.messages = msgs }
        }
        votesListener?.remove()
        votesListener = service.listenVotes(matchId: matchId) { [weak self] votes in
            Task { @MainActor in self?.votes = votes }
        }
        mvpVotesListener?.remove()
        mvpVotesListener = service.listenMvpVotes(matchId: matchId) { [weak self] votes in
            Task { @MainActor in self?.mvpVotes = votes }
        }
    }

    private func loadPlayers(uids: [String]) async {
        let missing = uids.filter { players[$0] == nil }
        guard !missing.isEmpty, let users = try? await service.fetchUsers(uids: missing) else { return }
        for u in users { if let id = u.id { players[id] = u } }
    }

    func pseudo(for uid: String) -> String { players[uid]?.pseudo ?? "?" }

    func send(text: String, matchId: String, sender: AppUser?) async {
        guard let sender, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? await service.sendMatchMessage(matchId: matchId, sender: sender, text: text)
    }

    func kick(uid: String, matchId: String) async {
        try? await service.kickParticipant(matchId: matchId, uid: uid, pseudo: pseudo(for: uid))
    }

    func cancelMatch(matchId: String) async {
        try? await service.cancelMatch(matchId: matchId)
    }

    func leave(matchId: String, uid: String?) async {
        guard let uid else { return }
        try? await service.leaveMatch(matchId: matchId, uid: uid)
    }

    func chooseSlot(matchId: String, uid: String, slot: Int) async {
        try? await service.setSlot(matchId: matchId, uid: uid, slot: slot)
    }

    func submitResult(match: Match, scoreA: Int, scoreB: Int, scorers: [String: Int]) async -> Bool {
        isWorking = true
        var ok = false
        do {
            try await service.submitMatchResult(match: match, scoreA: scoreA, scoreB: scoreB, scorers: scorers)
            ok = true
        } catch { errorMessage = error.localizedDescription }
        isWorking = false
        return ok
    }

    func vote(matchId: String, uid: String, validate: Bool) async {
        do { try await service.voteMatch(matchId: matchId, uid: uid, validate: validate) }
        catch { errorMessage = error.localizedDescription }
    }

    func voteMvp(matchId: String, voterUid: String, votedForUid: String) async {
        do { try await service.voteMvp(matchId: matchId, voterUid: voterUid, votedForUid: votedForUid) }
        catch { errorMessage = error.localizedDescription }
    }

    func myMvpVote(voterUid: String?) -> String? {
        guard let voterUid else { return nil }
        return mvpVotes[voterUid]
    }

    // Calculs votes
    func validateCount(participants: Int) -> Int { votes.values.filter { $0 == "validate" }.count }
    func contestCount(participants: Int) -> Int  { votes.values.filter { $0 == "contest" }.count }
    func hasVoted(uid: String?) -> Bool { guard let uid else { return false }; return votes[uid] != nil }
}

// MARK: - Vue principale

struct MatchSheetView: View {
    let matchId: String
    @EnvironmentObject var session: SessionViewModel
    @EnvironmentObject var tabBarVisibility: TabBarVisibility
    @StateObject private var viewModel = MatchSheetViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var messageText = ""
    @State private var showScoreSheet = false
    @State private var showCancelConfirm = false
    @State private var showLeaveConfirm = false
    @State private var profileUser: AppUser?
    @State private var closureError: String?
    @State private var showInviteFriend = false

    private var uid: String? { session.user?.id }
    private var isOrganizer: Bool { viewModel.match?.isOrganizer(uid) ?? false }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let match = viewModel.match {
                    ScrollView {
                        VStack(spacing: 14) {
                            // Terrain
                            PitchView(match: match, viewModel: viewModel, isOrganizer: isOrganizer)
                                .padding(.horizontal)
                                .environment(\.openProfile, { user in profileUser = user })

                            // Bandeau score final ou validation
                            statusBanner(match: match)

                            // Chat
                            chatSection
                        }
                        .padding(.vertical)
                    }

                    // Boutons du bas selon rôle + statut
                    bottomBar(match: match)

                    // Saisie chat
                    chatInput
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Pitcha.background)
            .navigationTitle("Feuille de match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Fermer") { dismiss() } }
                if let match = viewModel.match, !match.isPrivateMatch, !match.isFull {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showInviteFriend = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                        }
                    }
                }
            }
            .confirmationDialog("Annuler le match ?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
                Button("Annuler le match", role: .destructive) {
                    Task { await viewModel.cancelMatch(matchId: matchId); dismiss() }
                }
            } message: { Text("Les coins utilisés pour créer le match ne seront PAS remboursés.") }
            .confirmationDialog("Quitter le match ?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
                Button("Quitter", role: .destructive) {
                    Task { await viewModel.leave(matchId: matchId, uid: uid); dismiss() }
                }
            } message: { Text("Ton coin ne sera pas remboursé.") }
            .sheet(isPresented: $showScoreSheet) {
                if let match = viewModel.match {
                    EndMatchSheet(match: match, viewModel: viewModel)
                }
            }
            .sheet(item: $profileUser) { user in
                MiniProfileSheet(user: user, matchId: viewModel.match?.id)
                    .presentationDetents([.height(320)])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showInviteFriend) {
                if let match = viewModel.match {
                    InviteFriendToMatchSheet(match: match)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
            .alert("Impossible de clôturer", isPresented: .init(
                get: { closureError != nil },
                set: { if !$0 { closureError = nil } }
            )) {
                Button("OK") { closureError = nil }
            } message: { Text(closureError ?? "") }
            .onAppear {
                viewModel.listen(matchId: matchId)
                tabBarVisibility.isHidden = true
            }
            .onDisappear { tabBarVisibility.isHidden = false }
        }
    }

    // MARK: Bandeau statut

    @ViewBuilder
    private func statusBanner(match: Match) -> some View {
        switch match.status {
        case .pendingValidation, .played, .contested:
            // Le bandeau de vote reste affiché après clôture : les joueurs
            // voient le résultat final ET le taux de validation atteint,
            // sans pouvoir revoter (boutons masqués automatiquement).
            VotingBanner(match: match, viewModel: viewModel, uid: uid)
                .padding(.horizontal)
        default: EmptyView()
        }
    }

    // MARK: Boutons du bas

    @ViewBuilder
    private func bottomBar(match: Match) -> some View {
        if match.status == .open {
            if isOrganizer {
                HStack(spacing: 10) {
                    Button { showCancelConfirm = true } label: {
                        Label("Annuler", systemImage: "trash")
                            .font(.subheadline.bold()).foregroundStyle(.red)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(0.1)))
                    }
                    Button {
                        do {
                            try MatchIntegrityManager.checkClosureEligibility(match)
                            showScoreSheet = true
                        } catch {
                            closureError = error.localizedDescription
                        }
                    } label: {
                        Label("Fin du match", systemImage: "flag.checkered")
                            .font(.subheadline.bold()).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Pitcha.gradient))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            } else if match.isParticipant(uid) {
                Button { showLeaveConfirm = true } label: {
                    Text("Quitter le match")
                        .font(.subheadline.bold()).foregroundStyle(.red)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(0.08)))
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: Chat

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHAT DU MATCH")
                .font(.caption.weight(.heavy)).kerning(1.5)
                .foregroundStyle(.secondary).padding(.horizontal)
            LazyVStack(spacing: 10) {
                ForEach(viewModel.messages) { msg in
                    MessageBubble(message: msg, isMine: msg.senderId == uid, context: "match", contextId: matchId)
                }
            }
            .padding(.horizontal)
        }
    }

    private var chatInput: some View {
        HStack(spacing: 10) {
            TextField("Message...", text: $messageText)
                .submitLabel(.send).onSubmit { sendMsg() }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            Button { sendMsg() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                    .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : Pitcha.teal)
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    private func sendMsg() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""
        Task { await viewModel.send(text: text, matchId: matchId, sender: session.user) }
    }
}

// MARK: - Bandeau de vote (pendingValidation)

// MARK: - Inviter un ami à un match public

struct InviteFriendToMatchSheet: View {
    let match: Match
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var friends: [AppUser] = []
    @State private var isLoading = true
    @State private var invitedUids: Set<String> = []
    @State private var errorMessage: String?

    private var matchTitle: String {
        "Match \(match.type.displayName) • \(match.location)"
    }

    /// On exclut les amis déjà dans le match — inutile de les inviter.
    private var invitableFriends: [AppUser] {
        friends.filter { !match.participants.contains($0.id ?? "") }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if invitableFriends.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text(friends.isEmpty ? "Tu n'as pas encore d'amis à inviter." : "Tous tes amis sont déjà dans ce match.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(invitableFriends) { friend in
                        HStack(spacing: 12) {
                            AvatarImage(user: friend, size: 40)
                            Text(friend.pseudo)
                                .font(.subheadline.weight(.bold))
                            Spacer()
                            if invitedUids.contains(friend.id ?? "") {
                                Text("Envoyée")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            } else {
                                Button {
                                    invite(friend)
                                } label: {
                                    Text("Inviter")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(Pitcha.gradient))
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Inviter un ami")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } }
            }
            .task {
                guard let uids = session.user?.friends, !uids.isEmpty else { isLoading = false; return }
                friends = (try? await FirebaseService.shared.fetchUsers(uids: uids)) ?? []
                isLoading = false
            }
            .alert("Erreur", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func invite(_ friend: AppUser) {
        guard let friendUid = friend.id, let matchId = match.id,
              let myUid = session.user?.id, let myPseudo = session.user?.pseudo else { return }
        Task {
            do {
                try await FirebaseService.shared.inviteFriendToMatch(
                    matchId: matchId, matchTitle: matchTitle,
                    friendUid: friendUid, fromUid: myUid, fromPseudo: myPseudo
                )
                invitedUids.insert(friendUid)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct VotingBanner: View {
    let match: Match
    @ObservedObject var viewModel: MatchSheetViewModel
    let uid: String?

    private var total: Int { match.participants.count }
    private var validateCount: Int { viewModel.votes.values.filter { $0 == "validate" }.count }
    private var contestCount: Int  { viewModel.votes.values.filter { $0 == "contest" }.count }
    private var hasVoted: Bool { guard let uid else { return false }; return viewModel.votes[uid] != nil }
    private var myVote: String? { guard let uid else { return nil }; return viewModel.votes[uid] }

    private var isFinalized: Bool { match.status == .played || match.status == .contested }

    var body: some View {
        VStack(spacing: 12) {
            // En-tête : statut + score
            HStack(spacing: 8) {
                if isFinalized {
                    Image(systemName: match.status == .played ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(match.status == .played ? .green : .orange)
                }
                if let a = match.scoreA, let b = match.scoreB {
                    Text(isFinalized
                         ? (match.status == .played ? "Score validé : \(a) – \(b)" : "Match contesté : \(a) – \(b)")
                         : "Score soumis : \(a) – \(b)")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(isFinalized ? (match.status == .played ? .green : .orange) : Pitcha.navy)
                }
            }

            // Barre de vote (GeometryReader pour éviter NaN)
            GeometryReader { geo in
                let vRatio = total > 0 ? CGFloat(validateCount) / CGFloat(total) : 0
                let cRatio = total > 0 ? CGFloat(contestCount) / CGFloat(total) : 0
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.15))
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.green.opacity(0.8)).frame(width: w * vRatio)
                        Spacer()
                        Rectangle().fill(Color.orange.opacity(0.8)).frame(width: w * cRatio)
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 8)

            HStack {
                Label("\(validateCount) valident (75% requis)", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold()).foregroundStyle(.green)
                Spacer()
                Label("\(contestCount) contestent", systemImage: "xmark.circle.fill")
                    .font(.caption.bold()).foregroundStyle(.orange)
            }

            if !isFinalized, !hasVoted, match.isParticipant(uid) {
                HStack(spacing: 12) {
                    Button {
                        guard let uid, let matchId = match.id else { return }
                        Task { await viewModel.vote(matchId: matchId, uid: uid, validate: false) }
                    } label: {
                        Text("Contester")
                            .font(.subheadline.bold()).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
                    }
                    Button {
                        guard let uid, let matchId = match.id else { return }
                        Task { await viewModel.vote(matchId: matchId, uid: uid, validate: true) }
                    } label: {
                        Text("Valider ✓")
                            .font(.subheadline.bold()).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.green))
                    }
                }
            } else if isFinalized {
                Text(match.status == .played
                     ? (match.isRankedMatch ? "✅ PL distribués à tous les participants." : "✅ XP distribuée à tous les participants.")
                     : (match.isRankedMatch ? "⚠️ Match contesté." : "⚠️ XP réduite distribuée (score contesté)."))
                    .font(.footnote.bold()).foregroundStyle(.secondary)
            } else if hasVoted {
                Text("Tu as voté : \(myVote == "validate" ? "✓ Valider" : "⚠️ Contester")")
                    .font(.footnote.bold()).foregroundStyle(.secondary)
            }

            // MVP du match — badge une fois désigné, sinon vote ouvert
            // pendant la phase de validation.
            if let mvpUid = match.mvpUid {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Color(hex: "F2C740"))
                    Text("MVP du match : \(viewModel.pseudo(for: mvpUid))")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Pitcha.navy)
                }
                .padding(.top, 4)
            } else if !isFinalized, match.isParticipant(uid) {
                MvpVoteSection(match: match, viewModel: viewModel, uid: uid)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(.white).shadow(color: .black.opacity(0.06), radius: 8, y: 4))
    }
}

// MARK: - Vote MVP (pendant la phase de validation)

struct MvpVoteSection: View {
    let match: Match
    @ObservedObject var viewModel: MatchSheetViewModel
    let uid: String?

    private var myVote: String? { viewModel.myMvpVote(voterUid: uid) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Vote MVP du match")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(match.participants, id: \.self) { participantUid in
                        let isMe = participantUid == uid
                        let isSelected = myVote == participantUid
                        Button {
                            guard let uid, let matchId = match.id else { return }
                            Task { await viewModel.voteMvp(matchId: matchId, voterUid: uid, votedForUid: participantUid) }
                        } label: {
                            VStack(spacing: 4) {
                                Text(String(viewModel.pseudo(for: participantUid).prefix(2)).uppercased())
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(isSelected ? .white : Pitcha.navy)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        Circle().fill(
                                            isSelected
                                                ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "F2C740"), Color(hex: "B8860B")], startPoint: .top, endPoint: .bottom))
                                                : AnyShapeStyle(Color.gray.opacity(0.12))
                                        )
                                    )
                                Text(isMe ? "Toi" : viewModel.pseudo(for: participantUid))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 44)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Terrain

struct PitchView: View {
    let match: Match
    @ObservedObject var viewModel: MatchSheetViewModel
    let isOrganizer: Bool
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.openProfile) var openProfile

    private var bubbleSize: CGFloat {
        switch match.maxPlayers {
        case ..<12: return 46
        case 12..<18: return 42
        default: return 36
        }
    }

    private var bubbleSpacing: CGFloat {
        match.maxPlayers >= 18 ? 16 : 22
    }

    private var rowSpacing: CGFloat {
        match.maxPlayers >= 18 ? 10 : 14
    }

    private var totalRows: Int {
        let half = match.halfSlots
        let otherHalf = match.maxPlayers - half
        let rowsA = Int(ceil(Double(half) / 3.0))
        let rowsB = Int(ceil(Double(otherHalf) / 3.0))
        return rowsA + rowsB
    }

    private var pitchHeight: CGFloat {
        let rowHeight = bubbleSize + 16 + rowSpacing
        let verticalPadding: CGFloat = 52
        let gapBetweenTeams: CGFloat = 24
        let computed = CGFloat(totalRows) * rowHeight + verticalPadding + gapBetweenTeams
        return max(370, computed)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [Color(hex: "1A8D5F"), Color(hex: "0D4D3A")], startPoint: .top, endPoint: .bottom))
            PitchLines().stroke(.white.opacity(0.45), lineWidth: 1.5).padding(10)
            VStack {
                TeamSlotsView(match: match, range: 0..<match.halfSlots, color: Pitcha.mint, viewModel: viewModel, isOrganizer: isOrganizer, bubbleSize: bubbleSize, bubbleSpacing: bubbleSpacing, rowSpacing: rowSpacing)
                Spacer()
                TeamSlotsView(match: match, range: match.halfSlots..<match.maxPlayers, color: .orange, viewModel: viewModel, isOrganizer: isOrganizer, bubbleSize: bubbleSize, bubbleSpacing: bubbleSpacing, rowSpacing: rowSpacing)
            }
            .padding(.vertical, 26).padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: pitchHeight)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
    }
}

struct PitchLines: Shape {
    func path(in rect: CGRect) -> Path {
        // Guard contre width=0 ou NaN qui crashe CALayer
        guard rect.width > 0, rect.height > 0,
              !rect.width.isNaN, !rect.height.isNaN else { return Path() }
        var p = Path()
        p.addRoundedRect(in: rect, cornerSize: CGSize(width: 14, height: 14))
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addEllipse(in: CGRect(x: rect.midX - 32, y: rect.midY - 32, width: 64, height: 64))
        let bw = rect.width * 0.5
        p.addRect(CGRect(x: rect.midX - bw/2, y: rect.minY, width: bw, height: 44))
        p.addRect(CGRect(x: rect.midX - bw/2, y: rect.maxY - 44, width: bw, height: 44))
        return p
    }
}

struct TeamSlotsView: View {
    let match: Match
    let range: Range<Int>
    let color: Color
    @ObservedObject var viewModel: MatchSheetViewModel
    let isOrganizer: Bool
    var bubbleSize: CGFloat = 46
    var bubbleSpacing: CGFloat = 22
    var rowSpacing: CGFloat = 14
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.openProfile) var openProfile

    private var uid: String? { session.user?.id }
    private var rows: [[Int]] {
        let indices = Array(range)
        return stride(from: 0, to: indices.count, by: 3).map { Array(indices[$0..<min($0+3, indices.count)]) }
    }

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: bubbleSpacing) {
                    ForEach(row, id: \.self) { slot in
                        let occupant = match.resolvedSlots[slot]
                        if let occupantUid = occupant {
                            PlayerSlotBubble(uid: occupantUid, pseudo: viewModel.pseudo(for: occupantUid),
                                            color: color, isSelf: occupantUid == uid,
                                            matchId: match.id ?? "", isOrganizer: isOrganizer, viewModel: viewModel,
                                            bubbleSize: bubbleSize)
                            .onTapGesture {
                                if let user = viewModel.players[occupantUid] { openProfile(user) }
                            }
                        } else {
                            EmptySlotBubble(slot: slot, matchId: match.id ?? "", color: color, viewModel: viewModel, bubbleSize: bubbleSize)
                        }
                    }
                }
            }
        }
    }
}

struct PlayerSlotBubble: View {
    let uid: String; let pseudo: String; let color: Color; let isSelf: Bool
    let matchId: String; let isOrganizer: Bool
    @ObservedObject var viewModel: MatchSheetViewModel
    var bubbleSize: CGFloat = 46
    @EnvironmentObject var session: SessionViewModel
    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().fill(.white).frame(width: bubbleSize, height: bubbleSize)
                Text(String(pseudo.prefix(2)).uppercased()).font(.system(size: bubbleSize * 0.3, weight: .heavy)).foregroundStyle(Pitcha.navy)
                Circle().strokeBorder(color, lineWidth: 3).frame(width: bubbleSize, height: bubbleSize)
                if isSelf { Circle().strokeBorder(.white, lineWidth: 2).frame(width: bubbleSize + 6, height: bubbleSize + 6) }
            }
            Text(pseudo).font(.system(size: 10, weight: .bold)).foregroundStyle(.white).lineLimit(1).frame(maxWidth: 60)
        }
        .contextMenu {
            if isOrganizer && uid != session.user?.id {
                Button(role: .destructive) {
                    Task { await viewModel.kick(uid: uid, matchId: matchId) }
                } label: { Label("Exclure", systemImage: "person.badge.minus") }
            }
        }
    }
}

struct EmptySlotBubble: View {
    let slot: Int; let matchId: String; let color: Color
    @ObservedObject var viewModel: MatchSheetViewModel
    var bubbleSize: CGFloat = 46
    @EnvironmentObject var session: SessionViewModel
    var body: some View {
        VStack(spacing: 3) {
            Button {
                guard let uid = session.user?.id else { return }
                Task { await viewModel.chooseSlot(matchId: matchId, uid: uid, slot: slot) }
            } label: {
                ZStack {
                    Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                        .foregroundStyle(.white.opacity(0.55)).frame(width: bubbleSize, height: bubbleSize)
                    Image(systemName: "plus").font(.system(size: bubbleSize * 0.35, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                }
            }
            Text("Libre").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
        }
    }
}

// MARK: - EnvironmentKey openProfile

struct OpenProfileKey: EnvironmentKey {
    static var defaultValue: (AppUser) -> Void = { _ in }
}
extension EnvironmentValues {
    var openProfile: (AppUser) -> Void {
        get { self[OpenProfileKey.self] }
        set { self[OpenProfileKey.self] = newValue }
    }
}

// MARK: - Mini profil

struct MiniProfileSheet: View {
    let user: AppUser
    let matchId: String?
    @EnvironmentObject var session: SessionViewModel
    @State private var showReportBlock = false

    private var isMe: Bool { user.id == session.user?.id }

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            AvatarImage(user: user, size: 80)
            VStack(spacing: 4) {
                Text(user.pseudo).font(.title3.weight(.heavy)).foregroundStyle(Pitcha.navy)
                if let t = user.title, !t.isEmpty {
                    Text(t.uppercased()).font(.caption.weight(.semibold)).kerning(1.5)
                        .foregroundStyle(LinearGradient(colors: [Color(hex:"FFD700"), Color(hex:"D4AF37")], startPoint: .leading, endPoint: .trailing))
                }
                Text("Niveau \(user.level)").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(user.rankedDivisionEnum != nil ? Color(hex: "B8860B") : .secondary)
                Text(user.rankedDivisionEnum?.displayName ?? "Non classé")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Pitcha.navy)
                if user.rankedDivisionEnum != nil {
                    Text("· \(user.rankedPLValue) PL")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Signaler / Bloquer (masqué pour son propre profil)
            if !isMe, let uid = user.id {
                Button {
                    showReportBlock = true
                } label: {
                    Label("Signaler ou bloquer", systemImage: "flag")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }
                .sheet(isPresented: $showReportBlock) {
                    ReportBlockSheet(targetUid: uid, targetPseudo: user.pseudo, context: "match", contextId: matchId)
                }
            }

            Spacer()
        }
        .padding().background(Pitcha.background)
    }
}

// MARK: - Fin de match (saisie score + buteurs)

struct EndMatchSheet: View {
    let match: Match
    @ObservedObject var viewModel: MatchSheetViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var scoreA = 0
    @State private var scoreB = 0
    @State private var goals: [String: Int] = [:]

    private var totalGoalsA: Int { match.teamA.compactMap { $0 }.reduce(0) { $0 + (goals[$1] ?? 0) } }
    private var totalGoalsB: Int { match.teamB.compactMap { $0 }.reduce(0) { $0 + (goals[$1] ?? 0) } }
    // Les buts doivent être distribués EXACTEMENT — impossible de valider
    // avec des buts "orphelins" non attribués à un joueur.
    private var goalsValid: Bool { totalGoalsA == scoreA && totalGoalsB == scoreB }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 20) {
                        ScoreStepper(label: "Équipe A", color: Pitcha.mint, value: $scoreA)
                        Text("–").font(.title.weight(.heavy)).foregroundStyle(.secondary)
                        ScoreStepper(label: "Équipe B", color: .orange, value: $scoreB)
                    }
                    .padding(.top, 8)

                    if totalGoalsA > scoreA {
                        Text("⚠️ Buts Équipe A (\(totalGoalsA)) > score (\(scoreA))")
                            .font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                    } else if totalGoalsA < scoreA {
                        Text("Il reste \(scoreA - totalGoalsA) but(s) à distribuer côté Équipe A")
                            .font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                    }
                    if totalGoalsB > scoreB {
                        Text("⚠️ Buts Équipe B (\(totalGoalsB)) > score (\(scoreB))")
                            .font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                    } else if totalGoalsB < scoreB {
                        Text("Il reste \(scoreB - totalGoalsB) but(s) à distribuer côté Équipe B")
                            .font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Buteurs").font(.headline)
                        ForEach(match.participants, id: \.self) { uid in
                            let side = match.side(of: uid) ?? 0
                            let teamScore = side == 0 ? scoreA : scoreB
                            let teamGoals = side == 0 ? totalGoalsA : totalGoalsB
                            let remaining = max(0, teamScore - (teamGoals - (goals[uid] ?? 0)))
                            HStack {
                                Circle().fill(side == 0 ? Pitcha.mint : Color.orange).frame(width: 10, height: 10)
                                Text(viewModel.pseudo(for: uid)).font(.subheadline.bold())
                                Spacer()
                                Stepper(
                                    "\(goals[uid] ?? 0) ⚽️",
                                    value: Binding(get: { goals[uid] ?? 0 }, set: { goals[uid] = $0 }),
                                    in: 0...max(0, (goals[uid] ?? 0) + remaining)
                                )
                                .font(.subheadline.bold().monospacedDigit()).fixedSize()
                            }
                        }
                    }

                    if let err = viewModel.errorMessage {
                        Text(err).font(.footnote).foregroundStyle(.red)
                    }

                    // Note explicative sur la validation sociale
                    Label("Le score sera distribué après validation de 75% des joueurs.", systemImage: "person.2.fill")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)

                    Button {
                        Task {
                            let ok = await viewModel.submitResult(match: match, scoreA: scoreA, scoreB: scoreB,
                                                                  scorers: goals.filter { $0.value > 0 })
                            if ok { dismiss() }
                        }
                    } label: {
                        Group {
                            if viewModel.isWorking { ProgressView().tint(.white) }
                            else { Text("Soumettre le score").fontWeight(.bold) }
                        }
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 16)
                            .fill(goalsValid && !viewModel.isWorking ? Pitcha.gradient : LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing)))
                        .foregroundStyle(.white)
                    }
                    .disabled(!goalsValid || viewModel.isWorking)
                }
                .padding()
            }
            .navigationTitle("Résultat du match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Fermer") { dismiss() } } }
        }
    }
}

struct ScoreStepper: View {
    let label: String; let color: Color; @Binding var value: Int
    var body: some View {
        VStack(spacing: 8) {
            Text(label).font(.caption.weight(.heavy)).foregroundStyle(color)
            Text("\(value)").font(.system(size: 44, weight: .black, design: .rounded))
                .monospacedDigit().contentTransition(.numericText())
            HStack(spacing: 14) {
                Button { if value > 0 { withAnimation { value -= 1 } } } label: {
                    Image(systemName: "minus.circle.fill").font(.title2)
                        .foregroundStyle(value > 0 ? color : .gray.opacity(0.3))
                }
                Button { withAnimation { value += 1 } } label: {
                    Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(color)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
