import SwiftUI

struct TeamDetailView: View {
    let team: Team
    @EnvironmentObject var session: SessionViewModel
    @EnvironmentObject var tabBarVisibility: TabBarVisibility
    @StateObject private var viewModel = TeamDetailViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var messageText = ""
    @State private var showInviteSheet = false
    @State private var showOrganizerSheet = false
    @State private var showHighlightInfo = false
    @State private var showTeamInfo = false
    @State private var showLeaveConfirm = false
    @State private var showDeleteConfirm = false

    private var isOwner: Bool { team.ownerId == session.user?.id }

    private func sendCurrentMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""
        Task { await viewModel.send(text: text, team: team, sender: session.user) }
    }


    // Barre d'actions : Organiser / Highlight (au-dessus de la saisie)
    private var actionsBar: some View {
        HStack(spacing: 10) {
            Spacer()
            TeamActionChip(icon: "sportscourt.fill", label: "Organiser") {
                showOrganizerSheet = true
            }
            TeamActionChip(icon: "video.fill", label: "Highlight") {
                showHighlightInfo = true
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    // Barre de saisie du chat
    private var inputBar: some View {
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
    }

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.teamMatches.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.teamMatches) { match in
                            TeamMatchCard(match: match, team: team, viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }

            Divider()

            // Chat
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                isMine: message.senderId == session.user?.id
                            )
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    if let lastId = viewModel.messages.last?.id {
                        withAnimation(.snappy) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            actionsBar
            inputBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Le nom de l'équipe ouvre la fiche (toutes les actions y sont)
            ToolbarItem(placement: .principal) {
                Button {
                    showTeamInfo = true
                } label: {
                    HStack(spacing: 5) {
                        Text(team.name)
                            .font(.headline.weight(.heavy))
                        Image(systemName: "chevron.down")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(Pitcha.navy)
                }
            }
        }
        .sheet(isPresented: $showTeamInfo) {
            TeamInfoSheet(
                team: team,
                isOwner: isOwner,
                memberCount: viewModel.members.count,
                onInvite: { showTeamInfo = false; showInviteSheet = true },
                onLeave: { showTeamInfo = false; showLeaveConfirm = true },
                onDelete: { showTeamInfo = false; showDeleteConfirm = true }
            )
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showOrganizerSheet) {
            TeamMatchOrganizerView(team: team)
        }
        .sheet(isPresented: $showInviteSheet) {
            InvitePlayerSheet(viewModel: viewModel, team: team)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Quitter \(team.name) ?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button("Quitter", role: .destructive) {
                Task {
                    await viewModel.leaveTeam(team: team, uid: session.user?.id)
                    dismiss()
                }
            }
        }
        .confirmationDialog("Supprimer \(team.name) ?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Supprimer définitivement", role: .destructive) {
                Task {
                    await viewModel.deleteTeam(team: team)
                    dismiss()
                }
            }
        } message: {
            Text("Cette action est irréversible.")
        }
        .alert("Bientôt disponible 📹", isPresented: $showHighlightInfo) {
            Button("OK") {}
        } message: {
            Text("Les highlights arrivent dans une prochaine version : tu pourras partager tes plus belles actions avec ton équipe.")
        }
        .onAppear {
            viewModel.listen(team: team)
            tabBarVisibility.isHidden = true
        }
        .onDisappear {
            tabBarVisibility.isHidden = false
        }
    }
}

// MARK: - Bulle de message

struct MessageBubble: View {
    let message: ChatMessage
    let isMine: Bool

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: message.sentAt)
    }

    var body: some View {
        if message.senderId == "system" {
            Text(message.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.05)))
                .frame(maxWidth: .infinity)
        } else {
            bubble
        }
    }

    private var bubble: some View {
        HStack {
            if isMine { Spacer(minLength: 60) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                if !isMine {
                    Text(message.senderPseudo)
                        .font(.caption2.bold())
                        .foregroundStyle(.teal)
                }
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(isMine ? Color.teal : Color(.secondarySystemBackground))
                    .foregroundStyle(isMine ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                Text(timeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !isMine { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Sheet invitation

struct InvitePlayerSheet: View {
    @ObservedObject var viewModel: TeamDetailViewModel
    let team: Team
    @Environment(\.dismiss) private var dismiss

    @State private var pseudo = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Ajouter un joueur")
                .font(.title3.bold())
                .padding(.top, 24)

            Text("Entre le pseudo exact du joueur")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            PitchaTextField(icon: "person.fill", placeholder: "Pseudo", text: $pseudo)
                .textInputAutocapitalization(.never)
                .padding(.horizontal)

            if let result = viewModel.inviteResult {
                Text(result)
                    .font(.footnote)
                    .foregroundStyle(result.contains("✓") ? .green : .red)
            }

            Button {
                Task { await viewModel.invite(pseudo: pseudo, team: team) }
            } label: {
                Group {
                    if viewModel.isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text("Ajouter").fontWeight(.bold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(pseudo.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.4) : Color.teal)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(pseudo.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isWorking)
            .padding(.horizontal)

            Spacer()
        }
        .onDisappear {
            viewModel.inviteResult = nil
        }
    }
}


// MARK: - Carte de match d'équipe (Disponibles / Indisponibles)

struct TeamMatchCard: View {
    let match: Match
    let team: Team
    @ObservedObject var viewModel: TeamDetailViewModel
    @EnvironmentObject var session: SessionViewModel

    @State private var showDeleteConfirm = false

    private var uid: String? { session.user?.id }
    private var isAvailable: Bool { match.isParticipant(uid) }
    private var isUnavailable: Bool {
        guard let uid else { return false }
        return match.unavailableIds.contains(uid)
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE d MMM • HH:mm"
        return formatter.string(from: match.date).capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // En-tête
            HStack {
                Text(match.type.displayName)
                    .font(.caption.weight(.heavy))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Pitcha.gradient))
                    .foregroundStyle(.white)
                Spacer()
                Text(dateText)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                // L'organisateur peut supprimer son match
                if match.isOrganizer(uid) {
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.red.opacity(0.1)))
                    }
                }
            }

            Label(match.location, systemImage: "mappin.and.ellipse")
                .font(.subheadline.bold())
                .foregroundStyle(Pitcha.navy)
                .lineLimit(1)

            // Deux sections côte à côte
            HStack(alignment: .top, spacing: 14) {
                // Disponibles
                VStack(alignment: .leading, spacing: 8) {
                    Text("Disponibles")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Pitcha.tealDark)

                    ParticipantStack(
                        uids: match.participants,
                        emptySlots: max(0, min(match.maxPlayers - match.participants.count, 3)),
                        unavailableStyle: false,
                        viewModel: viewModel
                    )

                    Button {
                        Task { await viewModel.setAvailability(match: match, team: team, user: session.user, available: true) }
                    } label: {
                        Text(isAvailable ? "Inscrit ✓" : "Rejoindre")
                            .font(.caption.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(isAvailable ? AnyShapeStyle(Color.green) : AnyShapeStyle(Pitcha.gradient)))
                            .foregroundStyle(.white)
                    }
                    .disabled(isAvailable || (match.isFull && !isAvailable))
                }

                // Indisponibles
                VStack(alignment: .leading, spacing: 8) {
                    Text("Indisponibles")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.secondary)

                    ParticipantStack(
                        uids: match.unavailableIds,
                        emptySlots: match.unavailableIds.isEmpty ? 1 : 0,
                        unavailableStyle: true,
                        viewModel: viewModel
                    )

                    Button {
                        Task { await viewModel.setAvailability(match: match, team: team, user: session.user, available: false) }
                    } label: {
                        Text(isUnavailable ? "Indispo ✓" : "Indisponible")
                            .font(.caption.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.gray.opacity(isUnavailable ? 0.7 : 0.4)))
                            .foregroundStyle(.white)
                    }
                    .disabled(isUnavailable)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white)
                .shadow(color: .black.opacity(0.07), radius: 8, y: 4)
        )
        .confirmationDialog("Supprimer ce match ?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Supprimer le match", role: .destructive) {
                Task {
                    await viewModel.cancelTeamMatch(
                        match: match,
                        team: team,
                        organizerPseudo: session.user?.pseudo ?? ""
                    )
                }
            }
        } message: {
            Text("Les membres seront prévenus dans le chat.")
        }
    }
}

/// Cercles de participants empilés horizontalement (chevauchement -10pt),
/// avec slots vides en pointillé.
struct ParticipantStack: View {
    let uids: [String]
    let emptySlots: Int
    let unavailableStyle: Bool
    @ObservedObject var viewModel: TeamDetailViewModel

    private let maxVisible = 4

    var body: some View {
        HStack(spacing: -10) {
            ForEach(uids.prefix(maxVisible), id: \.self) { uid in
                if unavailableStyle {
                    UnavailableParticipantIcon(pseudo: viewModel.member(for: uid)?.pseudo ?? "?")
                } else {
                    ParticipantIcon(pseudo: viewModel.member(for: uid)?.pseudo ?? "?")
                }
            }
            if uids.count > maxVisible {
                ZStack {
                    Circle().fill(Color.black.opacity(0.08)).frame(width: 34, height: 34)
                    Text("+\(uids.count - maxVisible)")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Pitcha.navy)
                }
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            }
            ForEach(0..<emptySlots, id: \.self) { _ in
                EmptyParticipantSlot()
            }
        }
    }
}

struct ParticipantIcon: View {
    let pseudo: String

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Pitcha.teal, Pitcha.mint], startPoint: .top, endPoint: .bottom))
                .frame(width: 34, height: 34)
            Text(String(pseudo.prefix(2)).uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
        }
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
    }
}

struct UnavailableParticipantIcon: View {
    let pseudo: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.45))
                .frame(width: 34, height: 34)
            Text(String(pseudo.prefix(2)).uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
        }
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
    }
}

struct EmptyParticipantSlot: View {
    var body: some View {
        Circle()
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
            .foregroundStyle(Color.gray.opacity(0.5))
            .frame(width: 34, height: 34)
            .background(Circle().fill(.white))
    }
}


// MARK: - Chip d'action d'équipe (épuré, au-dessus de la saisie)

struct TeamActionChip: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption.bold())
            }
            .foregroundStyle(Pitcha.tealDark)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Pitcha.teal.opacity(0.10))
                    .overlay(Capsule().strokeBorder(Pitcha.teal.opacity(0.25), lineWidth: 1))
            )
        }
    }
}


// MARK: - Fiche équipe (tap sur le nom)

struct TeamInfoSheet: View {
    let team: Team
    let isOwner: Bool
    let memberCount: Int
    let onInvite: () -> Void
    let onLeave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            // En-tête : écusson + nom + membres
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(CrestPalette.color(named: team.crestColorName).gradient)
                        .frame(width: 72, height: 72)
                    Image(systemName: team.crestIcon ?? "shield.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                }
                Text(team.name)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Pitcha.navy)
                Text("\(memberCount) membre\(memberCount > 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 18)

            VStack(spacing: 10) {
                TeamInfoRow(icon: "person.badge.plus", label: "Ajouter un joueur", tint: Pitcha.tealDark, action: onInvite)
                if isOwner {
                    TeamInfoRow(icon: "trash", label: "Supprimer l'équipe", tint: .red, action: onDelete)
                } else {
                    TeamInfoRow(icon: "rectangle.portrait.and.arrow.right", label: "Quitter l'équipe", tint: .red, action: onLeave)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Pitcha.background)
    }
}

struct TeamInfoRow: View {
    let icon: String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .frame(width: 30)
                Text(label)
                    .font(.subheadline.bold())
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(tint)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
            )
        }
    }
}
