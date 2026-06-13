import SwiftUI
import Combine
import FirebaseFirestore

// MARK: - ViewModel

@MainActor
final class MatchSheetViewModel: ObservableObject {
    @Published var match: Match?
    @Published var players: [String: AppUser] = [:]
    @Published var messages: [ChatMessage] = []
    @Published var errorMessage: String?
    @Published var isWorking = false

    private let service = FirebaseService.shared
    private var matchListener: ListenerRegistration?
    private var messagesListener: ListenerRegistration?

    deinit { matchListener?.remove(); messagesListener?.remove() }

    func listen(matchId: String) {
        matchListener?.remove()
        matchListener = service.listenMatch(matchId: matchId) { [weak self] match in
            Task { @MainActor in
                self?.match = match
                if let uids = match?.participants { await self?.loadPlayers(uids: uids) }
            }
        }
        messagesListener?.remove()
        messagesListener = service.listenMatchMessages(matchId: matchId) { [weak self] msgs in
            Task { @MainActor in self?.messages = msgs }
        }
    }

    private func loadPlayers(uids: [String]) async {
        let missing = uids.filter { players[$0] == nil }
        guard !missing.isEmpty else { return }
        if let users = try? await service.fetchUsers(uids: missing) {
            for u in users { if let id = u.id { players[id] = u } }
        }
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

    func endMatch(match: Match, scoreA: Int, scoreB: Int, scorers: [String: Int]) async -> Bool {
        isWorking = true
        var ok = false
        do { try await service.endMatch(match: match, scoreA: scoreA, scoreB: scoreB, scorers: scorers); ok = true }
        catch { errorMessage = error.localizedDescription }
        isWorking = false
        return ok
    }
}

// MARK: - Vue principale

struct MatchSheetView: View {
    let matchId: String
    @EnvironmentObject var session: SessionViewModel
    @EnvironmentObject var tabBarVisibility: TabBarVisibility
    @StateObject private var viewModel = MatchSheetViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var messageText = ""
    @State private var showEndMatchSheet = false
    @State private var showCancelConfirm = false
    @State private var showLeaveConfirm = false
    @State private var profileUser: AppUser?

    private var uid: String? { session.user?.id }
    private var isOrganizer: Bool { viewModel.match?.isOrganizer(uid) ?? false }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let match = viewModel.match {
                    ScrollView {
                        VStack(spacing: 14) {
                            PitchView(match: match, viewModel: viewModel, isOrganizer: isOrganizer)
                                .padding(.horizontal)

                            if match.status == .played,
                               let a = match.scoreA, let b = match.scoreB {
                                Text("Score final : \(a) – \(b)")
                                    .font(.headline.weight(.heavy))
                                    .foregroundStyle(Pitcha.navy)
                            }

                            // Chat
                            VStack(alignment: .leading, spacing: 10) {
                                Text("CHAT DU MATCH")
                                    .font(.caption.weight(.heavy))
                                    .kerning(1.5)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)
                                LazyVStack(spacing: 10) {
                                    ForEach(viewModel.messages) { msg in
                                        MessageBubble(message: msg, isMine: msg.senderId == uid)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }

                    // Boutons organisateur en bas
                    if isOrganizer && match.status == .open {
                        HStack(spacing: 10) {
                            Button {
                                showCancelConfirm = true
                            } label: {
                                Label("Annuler", systemImage: "trash")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(0.1)))
                            }
                            Button {
                                showEndMatchSheet = true
                            } label: {
                                Label("Fin du match", systemImage: "flag.checkered")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Pitcha.gradient))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                    } else if !isOrganizer && match.isParticipant(uid) && match.status == .open {
                        Button {
                            showLeaveConfirm = true
                        } label: {
                            Text("Quitter le match")
                                .font(.subheadline.bold())
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(0.08)))
                                .padding(.horizontal)
                        }
                        .padding(.bottom, 4)
                    }

                    // Saisie chat
                    HStack(spacing: 10) {
                        TextField("Message...", text: $messageText)
                            .submitLabel(.send)
                            .onSubmit { sendMsg() }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        Button { sendMsg() } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : Pitcha.teal)
                        }
                        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Pitcha.background)
            .navigationTitle("Feuille de match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Fermer") { dismiss() } }
            }
            .confirmationDialog("Annuler le match ?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
                Button("Annuler le match", role: .destructive) {
                    Task { await viewModel.cancelMatch(matchId: matchId); dismiss() }
                }
            }
            .confirmationDialog("Quitter le match ?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
                Button("Quitter", role: .destructive) {
                    Task { await viewModel.leave(matchId: matchId, uid: uid); dismiss() }
                }
            } message: { Text("Ton coin ne sera pas remboursé.") }
            .sheet(isPresented: $showEndMatchSheet) {
                if let match = viewModel.match {
                    EndMatchSheet(match: match, viewModel: viewModel)
                }
            }
            .sheet(item: $profileUser) { user in
                MiniProfileSheet(user: user)
                    .presentationDetents([.height(320)])
                    .presentationDragIndicator(.visible)
            }
            .environment(\.openProfile, { user in profileUser = user })
            .onAppear {
                viewModel.listen(matchId: matchId)
                tabBarVisibility.isHidden = true
            }
            .onDisappear { tabBarVisibility.isHidden = false }
        }
    }

    private func sendMsg() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""
        Task { await viewModel.send(text: text, matchId: matchId, sender: session.user) }
    }
}

// MARK: - EnvironmentKey pour ouvrir un profil

struct OpenProfileKey: EnvironmentKey {
    static var defaultValue: (AppUser) -> Void = { _ in }
}
extension EnvironmentValues {
    var openProfile: (AppUser) -> Void {
        get { self[OpenProfileKey.self] }
        set { self[OpenProfileKey.self] = newValue }
    }
}

// MARK: - Terrain

struct PitchView: View {
    let match: Match
    @ObservedObject var viewModel: MatchSheetViewModel
    let isOrganizer: Bool
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [Color(hex: "1A8D5F"), Color(hex: "0D4D3A")], startPoint: .top, endPoint: .bottom))
            PitchLines().stroke(.white.opacity(0.45), lineWidth: 1.5).padding(10)
            VStack {
                TeamSlotsView(match: match, range: 0..<match.halfSlots, color: Pitcha.mint, viewModel: viewModel, isOrganizer: isOrganizer)
                Spacer()
                TeamSlotsView(match: match, range: match.halfSlots..<match.maxPlayers, color: .orange, viewModel: viewModel, isOrganizer: isOrganizer)
            }
            .padding(.vertical, 26)
            .padding(.horizontal, 16)
        }
        .frame(height: match.maxPlayers > 14 ? 460 : 370)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
    }
}

struct PitchLines: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: rect, cornerSize: CGSize(width: 14, height: 14))
        p.move(to: CGPoint(x: rect.minX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addEllipse(in: CGRect(x: rect.midX - 32, y: rect.midY - 32, width: 64, height: 64))
        let bw = rect.width * 0.5
        p.addRect(CGRect(x: rect.midX - bw/2, y: rect.minY, width: bw, height: 44))
        p.addRect(CGRect(x: rect.midX - bw/2, y: rect.maxY - 44, width: bw, height: 44))
        return p
    }
}

// MARK: - Slots d'une équipe

struct TeamSlotsView: View {
    let match: Match
    let range: Range<Int>
    let color: Color
    @ObservedObject var viewModel: MatchSheetViewModel
    let isOrganizer: Bool
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.openProfile) var openProfile

    private var uid: String? { session.user?.id }
    private var slots: [String?] { Array(match.resolvedSlots[range]) }
    private var rows: [[Int]] {
        let indices = Array(range)
        return stride(from: 0, to: indices.count, by: 3).map { Array(indices[$0..<min($0+3, indices.count)]) }
    }

    var body: some View {
        VStack(spacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 22) {
                    ForEach(row, id: \.self) { slot in
                        let occupant = match.resolvedSlots[slot]
                        if let occupantUid = occupant {
                            let pseudo = viewModel.pseudo(for: occupantUid)
                            PlayerSlotBubble(
                                uid: occupantUid,
                                pseudo: pseudo,
                                color: color,
                                isSelf: occupantUid == uid,
                                matchId: match.id ?? "",
                                isOrganizer: isOrganizer,
                                viewModel: viewModel
                            )
                            .onTapGesture {
                                if let user = viewModel.players[occupantUid] {
                                    openProfile(user)
                                }
                            }
                        } else {
                            EmptySlotBubble(slot: slot, matchId: match.id ?? "", color: color, viewModel: viewModel)
                        }
                    }
                }
            }
        }
    }
}

// Slot occupé
struct PlayerSlotBubble: View {
    let uid: String
    let pseudo: String
    let color: Color
    let isSelf: Bool
    let matchId: String
    let isOrganizer: Bool
    @ObservedObject var viewModel: MatchSheetViewModel
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().fill(.white).frame(width: 46, height: 46)
                Text(String(pseudo.prefix(2)).uppercased())
                    .font(.system(size: 14, weight: .heavy)).foregroundStyle(Pitcha.navy)
                Circle().strokeBorder(color, lineWidth: 3).frame(width: 46, height: 46)
                if isSelf {
                    Circle().strokeBorder(.white, lineWidth: 2)
                        .frame(width: 52, height: 52)
                }
            }
            Text(pseudo).font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white).lineLimit(1).frame(maxWidth: 60)
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

// Slot vide : le + permet de se placer
struct EmptySlotBubble: View {
    let slot: Int
    let matchId: String
    let color: Color
    @ObservedObject var viewModel: MatchSheetViewModel
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        VStack(spacing: 3) {
            Button {
                guard let uid = session.user?.id else { return }
                Task { await viewModel.chooseSlot(matchId: matchId, uid: uid, slot: slot) }
            } label: {
                ZStack {
                    Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                        .foregroundStyle(.white.opacity(0.55)).frame(width: 46, height: 46)
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Text("Libre").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
        }
    }
}

// MARK: - Mini profil (tap sur une bulle)

struct MiniProfileSheet: View {
    let user: AppUser
    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            ZStack {
                Circle().fill(Pitcha.gradient).frame(width: 80, height: 80)
                if let base64 = user.photoBase64, let data = Data(base64Encoded: base64), let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 80, height: 80).clipShape(Circle())
                } else {
                    Text(user.initials).font(.system(size: 28, weight: .black)).foregroundStyle(.white)
                }
            }
            VStack(spacing: 4) {
                Text(user.pseudo).font(.title3.weight(.heavy)).foregroundStyle(Pitcha.navy)
                if let title = user.title, !title.isEmpty {
                    Text(title.uppercased())
                        .font(.caption.weight(.semibold)).kerning(1.5)
                        .foregroundStyle(LinearGradient(colors: [Color(hex:"FFD700"), Color(hex:"D4AF37")], startPoint: .leading, endPoint: .trailing))
                }
                Text("Niveau \(user.level) • \(user.overall) général")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 20) {
                ForEach(user.displayAttributes.all, id: \.key) { attr in
                    VStack(spacing: 2) {
                        Text(attr.key).font(.system(size: 10, weight: .heavy)).foregroundStyle(.secondary)
                        Text("\(attr.value)").font(.system(size: 16, weight: .black)).foregroundStyle(Pitcha.navy)
                    }
                }
            }
            .padding(.horizontal)
            Spacer()
        }
        .padding()
        .background(Pitcha.background)
    }
}

// MARK: - Fin de match (score lié aux buts)

struct EndMatchSheet: View {
    let match: Match
    @ObservedObject var viewModel: MatchSheetViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var scoreA = 0
    @State private var scoreB = 0
    @State private var goals: [String: Int] = [:]

    // Contrôle : buts par équipe ne peuvent excéder leur score
    private var totalGoalsA: Int { match.teamA.compactMap { $0 }.reduce(0) { $0 + (goals[$1] ?? 0) } }
    private var totalGoalsB: Int { match.teamB.compactMap { $0 }.reduce(0) { $0 + (goals[$1] ?? 0) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // Score
                    HStack(spacing: 20) {
                        ScoreStepper(label: "Équipe A", color: Pitcha.mint, value: $scoreA)
                        Text("–").font(.title.weight(.heavy)).foregroundStyle(.secondary)
                        ScoreStepper(label: "Équipe B", color: .orange, value: $scoreB)
                    }
                    .padding(.top, 8)

                    // Avertissement si buts > score
                    if totalGoalsA > scoreA {
                        Text("⚠️ Les buts de l'Équipe A (\(totalGoalsA)) dépassent le score (\(scoreA))")
                            .font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                    if totalGoalsB > scoreB {
                        Text("⚠️ Les buts de l'Équipe B (\(totalGoalsB)) dépassent le score (\(scoreB))")
                            .font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                    }

                    Divider()

                    // Buteurs
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
                                    value: Binding(
                                        get: { goals[uid] ?? 0 },
                                        set: { goals[uid] = $0 }
                                    ),
                                    in: 0...max(0, (goals[uid] ?? 0) + remaining)
                                )
                                .font(.subheadline.bold().monospacedDigit())
                                .fixedSize()
                            }
                        }
                    }

                    if let err = viewModel.errorMessage {
                        Text(err).font(.footnote).foregroundStyle(.red)
                    }

                    let canSubmit = totalGoalsA <= scoreA && totalGoalsB <= scoreB && !viewModel.isWorking
                    Button {
                        Task {
                            let ok = await viewModel.endMatch(
                                match: match, scoreA: scoreA, scoreB: scoreB,
                                scorers: goals.filter { $0.value > 0 }
                            )
                            if ok { dismiss() }
                        }
                    } label: {
                        Group {
                            if viewModel.isWorking { ProgressView().tint(.white) }
                            else { Text("Valider le résultat").fontWeight(.bold) }
                        }
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 16).fill(canSubmit ? Pitcha.gradient : LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing)))
                        .foregroundStyle(.white)
                    }
                    .disabled(!canSubmit)
                }
                .padding()
            }
            .navigationTitle("Fin du match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Fermer") { dismiss() } } }
        }
    }
}

struct ScoreStepper: View {
    let label: String
    let color: Color
    @Binding var value: Int
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
