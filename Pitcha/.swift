import SwiftUI
import FirebaseFirestore
import Combine

// MARK: - ViewModel feuille de match

@MainActor
final class MatchSheetViewModel: ObservableObject {

    @Published var match: Match?
    @Published var players: [String: AppUser] = [:]   // uid -> profil
    @Published var messages: [ChatMessage] = []
    @Published var errorMessage: String?
    @Published var isWorking = false

    private let service = FirebaseService.shared
    private var matchListener: ListenerRegistration?
    private var messagesListener: ListenerRegistration?

    deinit {
        matchListener?.remove()
        messagesListener?.remove()
    }

    func listen(matchId: String) {
        matchListener?.remove()
        matchListener = service.listenMatch(matchId: matchId) { [weak self] match in
            Task { @MainActor in
                self?.match = match
                if let participants = match?.participants {
                    await self?.loadPlayers(uids: participants)
                }
            }
        }
        messagesListener?.remove()
        messagesListener = service.listenMatchMessages(matchId: matchId) { [weak self] messages in
            Task { @MainActor in self?.messages = messages }
        }
    }

    private func loadPlayers(uids: [String]) async {
        let missing = uids.filter { players[$0] == nil }
        guard !missing.isEmpty else { return }
        if let users = try? await service.fetchUsers(uids: missing) {
            for user in users {
                if let uid = user.id { players[uid] = user }
            }
        }
    }

    func pseudo(for uid: String) -> String {
        players[uid]?.pseudo ?? "?"
    }

    // MARK: Chat

    func send(text: String, matchId: String, sender: AppUser?) async {
        guard let sender else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        do {
            try await service.sendMatchMessage(matchId: matchId, sender: sender, text: clean)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Actions organisateur

    func kick(uid: String, matchId: String) async {
        do {
            try await service.kickParticipant(matchId: matchId, uid: uid, pseudo: pseudo(for: uid))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelMatch(matchId: String) async {
        do {
            try await service.cancelMatch(matchId: matchId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func endMatch(match: Match, scoreA: Int, scoreB: Int, scorers: [String: Int]) async -> Bool {
        isWorking = true
        errorMessage = nil
        var success = false
        do {
            try await service.endMatch(match: match, scoreA: scoreA, scoreB: scoreB, scorers: scorers)
            success = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
        return success
    }

    // MARK: Participant

    func leave(matchId: String, uid: String?) async {
        guard let uid else { return }
        do {
            try await service.leaveMatch(matchId: matchId, uid: uid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Feuille de match

struct MatchSheetView: View {
    let matchId: String
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var viewModel = MatchSheetViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var messageText = ""
    @State private var showCancelConfirm = false
    @State private var showLeaveConfirm = false
    @State private var showEndMatchSheet = false

    private var isOrganizer: Bool {
        viewModel.match?.isOrganizer(session.user?.id) ?? false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let match = viewModel.match {
                    ScrollView {
                        VStack(spacing: 14) {
                            // En-tête match
                            MatchSheetHeader(match: match)

                            // Terrain avec les bulles
                            PitchView(match: match, viewModel: viewModel, isOrganizer: isOrganizer)
                                .padding(.horizontal)

                            if match.status == .played, let a = match.scoreA, let b = match.scoreB {
                                Text("Score final : \(a) - \(b)")
                                    .font(.headline.weight(.heavy))
                                    .foregroundStyle(Pitcha.navy)
                            }

                            if let error = viewModel.errorMessage {
                                Text(error)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }

                            // Chat du match
                            VStack(alignment: .leading, spacing: 10) {
                                Text("CHAT DU MATCH")
                                    .font(.caption.weight(.heavy))
                                    .kerning(1.5)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)

                                LazyVStack(spacing: 10) {
                                    ForEach(viewModel.messages) { message in
                                        MessageBubble(
                                            message: message,
                                            isMine: message.senderId == session.user?.id
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .padding(.top, 6)
                        }
                        .padding(.vertical)
                    }

                    // Barre de saisie
                    HStack(spacing: 10) {
                        TextField("Message...", text: $messageText)
                            .submitLabel(.send)
                            .onSubmit { sendCurrentMessage() }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 20))

                        Button { sendCurrentMessage() } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : Pitcha.teal)
                        }
                        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Pitcha.background)
            .navigationTitle("Feuille de match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let match = viewModel.match, match.status == .open {
                        Menu {
                            if isOrganizer {
                                Button {
                                    showEndMatchSheet = true
                                } label: {
                                    Label("Mettre fin au match", systemImage: "flag.checkered")
                                }
                                Button(role: .destructive) {
                                    showCancelConfirm = true
                                } label: {
                                    Label("Annuler le match", systemImage: "trash")
                                }
                            } else if match.isParticipant(session.user?.id) {
                                Button(role: .destructive) {
                                    showLeaveConfirm = true
                                } label: {
                                    Label("Quitter le match", systemImage: "rectangle.portrait.and.arrow.right")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog("Annuler ce match ?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
                Button("Annuler le match", role: .destructive) {
                    Task {
                        await viewModel.cancelMatch(matchId: matchId)
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Quitter ce match ?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
                Button("Quitter", role: .destructive) {
                    Task {
                        await viewModel.leave(matchId: matchId, uid: session.user?.id)
                        dismiss()
                    }
                }
            } message: {
                Text("Ton coin ne sera pas remboursé.")
            }
            .sheet(isPresented: $showEndMatchSheet) {
                if let match = viewModel.match {
                    EndMatchSheet(match: match, viewModel: viewModel)
                }
            }
            .onAppear {
                viewModel.listen(matchId: matchId)
            }
        }
    }

    private func sendCurrentMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""
        Task { await viewModel.send(text: text, matchId: matchId, sender: session.user) }
    }
}

// MARK: - En-tête

struct MatchSheetHeader: View {
    let match: Match

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE d MMM • HH:mm"
        return formatter.string(from: match.date).capitalized
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("Match \(match.type.displayName.uppercased())")
                .font(.headline.weight(.heavy))
                .foregroundStyle(Pitcha.navy)
            Text("\(match.location) • \(dateText)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(match.participants.count)/\(match.maxPlayers) joueurs • Par \(match.organizerPseudo)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Terrain avec bulles

struct PitchView: View {
    let match: Match
    @ObservedObject var viewModel: MatchSheetViewModel
    let isOrganizer: Bool
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        ZStack {
            // Pelouse
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "1A8D5F"), Color(hex: "0D4D3A")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Lignes du terrain
            PitchLines()
                .stroke(.white.opacity(0.45), lineWidth: 1.5)
                .padding(10)

            // Bulles des deux équipes
            VStack {
                TeamSlots(
                    uids: match.teamA,
                    slotCount: match.halfSlots,
                    color: Pitcha.mint,
                    match: match,
                    viewModel: viewModel,
                    isOrganizer: isOrganizer
                )
                Spacer()
                TeamSlots(
                    uids: match.teamB,
                    slotCount: match.maxPlayers - match.halfSlots,
                    color: .orange,
                    match: match,
                    viewModel: viewModel,
                    isOrganizer: isOrganizer
                )
            }
            .padding(.vertical, 26)
            .padding(.horizontal, 16)
        }
        .frame(height: match.maxPlayers > 14 ? 460 : 380)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
    }
}

/// Lignes : bordure, médiane, rond central, surfaces.
struct PitchLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: 14, height: 14))
        // Ligne médiane
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        // Rond central
        path.addEllipse(in: CGRect(x: rect.midX - 32, y: rect.midY - 32, width: 64, height: 64))
        // Surfaces
        let boxWidth = rect.width * 0.5
        path.addRect(CGRect(x: rect.midX - boxWidth / 2, y: rect.minY, width: boxWidth, height: 44))
        path.addRect(CGRect(x: rect.midX - boxWidth / 2, y: rect.maxY - 44, width: boxWidth, height: 44))
        return path
    }
}

/// Bulles d'une équipe, en rangées de 3 max.
struct TeamSlots: View {
    let uids: [String]
    let slotCount: Int
    let color: Color
    let match: Match
    @ObservedObject var viewModel: MatchSheetViewModel
    let isOrganizer: Bool
    @EnvironmentObject var session: SessionViewModel

    private var rows: [[Int]] {
        let indices = Array(0..<slotCount)
        return stride(from: 0, to: indices.count, by: 3).map {
            Array(indices[$0..<min($0 + 3, indices.count)])
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 22) {
                    ForEach(row, id: \.self) { slot in
                        if slot < uids.count {
                            PlayerSlot(
                                uid: uids[slot],
                                pseudo: viewModel.pseudo(for: uids[slot]),
                                color: color,
                                match: match,
                                viewModel: viewModel,
                                isOrganizer: isOrganizer
                            )
                        } else {
                            Circle()
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                .foregroundStyle(.white.opacity(0.55))
                                .frame(width: 46, height: 46)
                        }
                    }
                }
            }
        }
    }
}

struct PlayerSlot: View {
    let uid: String
    let pseudo: String
    let color: Color
    let match: Match
    @ObservedObject var viewModel: MatchSheetViewModel
    let isOrganizer: Bool
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 46, height: 46)
                Text(String(pseudo.prefix(2)).uppercased())
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Pitcha.navy)
                Circle()
                    .strokeBorder(color, lineWidth: 3)
                    .frame(width: 46, height: 46)
            }
            Text(pseudo)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: 60)
        }
        .contextMenu {
            // L'organisateur peut exclure (sauf lui-même)
            if isOrganizer, uid != session.user?.id, match.status == .open, let matchId = match.id {
                Button(role: .destructive) {
                    Task { await viewModel.kick(uid: uid, matchId: matchId) }
                } label: {
                    Label("Exclure du match", systemImage: "person.badge.minus")
                }
            }
        }
    }
}

// MARK: - Fin de match : score + buteurs

struct EndMatchSheet: View {
    let match: Match
    @ObservedObject var viewModel: MatchSheetViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var scoreA = 0
    @State private var scoreB = 0
    @State private var goals: [String: Int] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // Score
                    HStack(spacing: 20) {
                        ScoreStepper(label: "Équipe A", color: Pitcha.mint, value: $scoreA)
                        Text("-")
                            .font(.title.weight(.heavy))
                            .foregroundStyle(.secondary)
                        ScoreStepper(label: "Équipe B", color: .orange, value: $scoreB)
                    }
                    .padding(.top, 8)

                    Divider()

                    // Buteurs
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Buteurs")
                            .font(.headline)
                        ForEach(match.participants, id: \.self) { uid in
                            HStack {
                                Circle()
                                    .fill(match.side(of: uid) == 0 ? Pitcha.mint : Color.orange)
                                    .frame(width: 10, height: 10)
                                Text(viewModel.pseudo(for: uid))
                                    .font(.subheadline.bold())
                                Spacer()
                                Stepper(
                                    "\(goals[uid] ?? 0) ⚽️",
                                    value: Binding(
                                        get: { goals[uid] ?? 0 },
                                        set: { goals[uid] = $0 }
                                    ),
                                    in: 0...20
                                )
                                .font(.subheadline.bold().monospacedDigit())
                                .fixedSize()
                            }
                        }
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task {
                            let success = await viewModel.endMatch(
                                match: match,
                                scoreA: scoreA,
                                scoreB: scoreB,
                                scorers: goals.filter { $0.value > 0 }
                            )
                            if success { dismiss() }
                        }
                    } label: {
                        Group {
                            if viewModel.isWorking {
                                ProgressView().tint(.white)
                            } else {
                                Text("Valider le résultat").fontWeight(.bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Pitcha.gradient))
                        .foregroundStyle(.white)
                    }
                    .disabled(viewModel.isWorking)
                }
                .padding()
            }
            .navigationTitle("Fin du match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

struct ScoreStepper: View {
    let label: String
    let color: Color
    @Binding var value: Int

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.heavy))
                .foregroundStyle(color)
            Text("\(value)")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            HStack(spacing: 14) {
                Button {
                    if value > 0 { withAnimation(.snappy) { value -= 1 } }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(value > 0 ? color : .gray.opacity(0.3))
                }
                Button {
                    withAnimation(.snappy) { value += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(color)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
