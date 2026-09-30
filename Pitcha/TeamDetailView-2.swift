import SwiftUI
import AVFoundation

struct TeamDetailView: View {
    let team: Team
    @EnvironmentObject var session: SessionViewModel
    @EnvironmentObject var tabBarVisibility: TabBarVisibility
    @EnvironmentObject var network: NetworkMonitor
    @StateObject private var viewModel = TeamDetailViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var messageText = ""
    @FocusState private var isMessageFieldFocused: Bool
    @State private var showInviteSheet = false
    @State private var showOrganizerSheet = false
    @State private var showHighlightInfo = false
    @State private var showTeamRanking = false
    @State private var showTeamInfo = false
    @State private var showLeaveConfirm = false
    @State private var showDeleteConfirm = false

    private var isOwner: Bool { team.ownerId == session.user?.id }

    private func sendCurrentMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""
        Task { await viewModel.send(text: text, team: team, sender: session.user) }
        isMessageFieldFocused = true
    }


    // Barre d'actions : Highlight · Organiser · Classement — centrés
    private var actionsBar: some View {
        HStack(spacing: 12) {
            Spacer()
            TeamActionChip(icon: "video.fill", label: "Highlight") {
                showHighlightInfo = true
            }
            TeamActionChip(icon: "sportscourt.fill", label: "Organiser") {
                showOrganizerSheet = true
            }
            TeamActionChip(icon: "list.number", label: "Classement") {
                showTeamRanking = true
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    // Barre de saisie du chat — texte, photo et vocal (comme le chat privé/club)
    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message...", text: $messageText)
                .focused($isMessageFieldFocused)
                .disabled(!network.isConnected)
                .submitLabel(.send)
                .onSubmit { sendCurrentMessage() }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))

            if messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PhotoPickerButton { data in
                    guard let teamId = team.id, let sender = session.user else { return }
                    Task { try? await FirebaseService.shared.sendPhotoTeamMessage(teamId: teamId, sender: sender, photoData: data) }
                }
                .disabled(!network.isConnected)
                VoiceRecordButton { fileURL, duration in
                    guard let teamId = team.id, let sender = session.user else { return }
                    Task { try? await FirebaseService.shared.sendVoiceTeamMessage(teamId: teamId, sender: sender, fileURL: fileURL, duration: duration) }
                }
                .disabled(!network.isConnected)
            } else {
                Button { sendCurrentMessage() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(!network.isConnected ? .gray : Pitcha.teal)
                }
                .disabled(!network.isConnected)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .gesture(
            DragGesture(minimumDistance: 15)
                .onEnded { value in
                    if value.translation.height > 15 {
                        isMessageFieldFocused = false
                    }
                }
        )
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
            if !network.isConnected { OfflineChatBanner() }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                isMine: message.senderId == session.user?.id,
                                context: "team",
                                contextId: team.id
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
                members: viewModel.members,
                onInvite: { showTeamInfo = false; showInviteSheet = true },
                onLeave: { showTeamInfo = false; showLeaveConfirm = true },
                onDelete: { showTeamInfo = false; showDeleteConfirm = true }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showOrganizerSheet) {
            TeamMatchOrganizerView(team: team)
        }
        .sheet(isPresented: $showInviteSheet) {
            InvitePlayerSheet(viewModel: viewModel, team: team)
                .presentationDetents([.medium, .large])
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
        .sheet(isPresented: $showTeamRanking) {
            TeamRankingSheet(team: team, members: viewModel.members)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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

// MARK: - Bulle de message (texte / photo / vocal)

struct MessageBubble: View {
    let message: ChatMessage
    let isMine: Bool
    /// Contexte d'où vient ce message, pour le signalement ("team", "dm" ou "club").
    /// Optionnel pour rester compatible avec les appels existants.
    var context: String = "team"
    var contextId: String? = nil
    @EnvironmentObject var session: SessionViewModel
    @State private var showReportBlock = false

    /// Masque le contenu si l'expéditeur est bloqué par l'utilisateur.
    private var isFromBlockedUser: Bool {
        session.user?.hasBlocked(message.senderId) ?? false
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: message.sentAt ?? Date())
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
                    // Tap sur le pseudo = signaler/bloquer cet utilisateur
                    Button {
                        showReportBlock = true
                    } label: {
                        Text(message.senderPseudo)
                            .font(.caption2.bold())
                            .foregroundStyle(.teal)
                    }
                    .sheet(isPresented: $showReportBlock) {
                        ReportBlockSheet(
                            targetUid: message.senderId,
                            targetPseudo: message.senderPseudo,
                            context: context,
                            contextId: contextId
                        )
                    }
                }
                content
                Text(timeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !isMine { Spacer(minLength: 60) }
        }
    }

    // Contenu du message : texte, photo ou vocal — avant, seul le texte
    // était affiché, donc une photo ou un vocal envoyé créait une bulle
    // vide (message.text reste "" pour ces deux types).
    @ViewBuilder
    private var content: some View {
        if isFromBlockedUser {
            Text("🚫 Message masqué (utilisateur bloqué)")
                .italic()
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.gray.opacity(0.15))
                .foregroundStyle(.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        } else if message.isPhoto, let urlString = message.photoURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    ZStack {
                        Color.gray.opacity(0.15)
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                default:
                    ZStack {
                        Color.gray.opacity(0.08)
                        ProgressView()
                    }
                }
            }
            .frame(width: 210, height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .clipped()
        } else if message.isVoice, let urlString = message.voiceURL, let url = URL(string: urlString) {
            VoiceMessageBubble(url: url, duration: message.voiceDuration ?? 0, isMine: isMine)
        } else {
            Text(message.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isMine ? Color.teal : Color(.secondarySystemBackground))
                .foregroundStyle(isMine ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}

// MARK: - Bulle de message vocal (lecture inline)

struct VoiceMessageBubble: View {
    let url: URL
    let duration: Double
    let isMine: Bool

    @State private var player: AVPlayer?
    @State private var isPlaying = false

    private var durationText: String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        Button {
            togglePlayback()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.subheadline)
                Image(systemName: "waveform")
                    .font(.subheadline)
                Text(durationText)
                    .font(.caption.bold())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isMine ? Color.teal : Color(.secondarySystemBackground))
            .foregroundStyle(isMine ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .onDisappear {
            player?.pause()
        }
    }

    private func togglePlayback() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            isPlaying = false
        }
        newPlayer.play()
        isPlaying = true
    }
}

// MARK: - Sheet invitation (pseudo exact OU choix parmi les amis)

struct InvitePlayerSheet: View {
    @ObservedObject var viewModel: TeamDetailViewModel
    let team: Team
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var pseudo = ""
    @State private var friends: [AppUser] = []

    // Seuls les amis qui ne sont pas déjà dans l'équipe sont proposés.
    private var availableFriends: [AppUser] {
        friends.filter { friend in
            guard let uid = friend.id else { return false }
            return !team.memberIds.contains(uid)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Ajouter un joueur")
                .font(.title3.bold())
                .padding(.top, 24)

            Text("Seuls tes amis peuvent rejoindre l'équipe")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            PitchaTextField(icon: "person.fill", placeholder: "Pseudo exact", text: $pseudo)
                .textInputAutocapitalization(.never)
                .padding(.horizontal)

            if let result = viewModel.inviteResult {
                Text(result)
                    .font(.footnote)
                    .foregroundStyle(result.contains("✓") ? .green : .red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                Task {
                    await viewModel.invite(
                        pseudo: pseudo,
                        team: team,
                        friendUids: session.user?.friends ?? []
                    )
                }
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

            Divider()
                .padding(.horizontal)

            if availableFriends.isEmpty {
                VStack(spacing: 6) {
                    Text("Aucun ami disponible")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Text("Tous tes amis sont déjà dans l'équipe, ou tu n'as pas encore d'amis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                .padding(.top, 20)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tes amis")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Pitcha.navy)
                        .padding(.horizontal)

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(availableFriends) { friend in
                                Button {
                                    guard let uid = friend.id else { return }
                                    Task { await viewModel.inviteFriend(uid: uid, pseudo: friend.pseudo, team: team) }
                                } label: {
                                    HStack(spacing: 12) {
                                        InitialsAvatar(text: friend.pseudo, size: 40, cornerStyle: .circle)
                                        Text(friend.pseudo)
                                            .font(.subheadline.weight(.heavy))
                                            .foregroundStyle(Pitcha.navy)
                                        Spacer()
                                        if viewModel.isWorking {
                                            ProgressView()
                                        } else {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(Pitcha.teal)
                                        }
                                    }
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.04)))
                                }
                                .buttonStyle(.plain)
                                .disabled(viewModel.isWorking)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .task {
            friends = (try? await FirebaseService.shared.fetchUsers(uids: session.user?.friends ?? [])) ?? []
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
    @State private var selectedMember: AppUser?

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
                        viewModel: viewModel,
                        selectedMember: $selectedMember
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
                        viewModel: viewModel,
                        selectedMember: $selectedMember
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
        .sheet(item: $selectedMember) { member in
            PublicProfileSheet(member: member)
        }
    }
}

/// Cercles de participants empilés horizontalement (chevauchement -10pt),
/// avec slots vides en pointillé. Tap sur une bulle = voir le profil.
struct ParticipantStack: View {
    let uids: [String]
    let emptySlots: Int
    let unavailableStyle: Bool
    @ObservedObject var viewModel: TeamDetailViewModel
    @Binding var selectedMember: AppUser?

    private let maxVisible = 4

    var body: some View {
        HStack(spacing: -10) {
            ForEach(uids.prefix(maxVisible), id: \.self) { uid in
                Button {
                    if let member = viewModel.member(for: uid) { selectedMember = member }
                } label: {
                    if unavailableStyle {
                        UnavailableParticipantIcon(pseudo: viewModel.member(for: uid)?.pseudo ?? "?")
                    } else {
                        ParticipantIcon(pseudo: viewModel.member(for: uid)?.pseudo ?? "?")
                    }
                }
                .buttonStyle(.plain)
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
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
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


// MARK: - Fiche équipe (tap sur le nom) — actions + liste des membres

struct TeamInfoSheet: View {
    let team: Team
    let isOwner: Bool
    let members: [AppUser]
    let onInvite: () -> Void
    let onLeave: () -> Void
    let onDelete: () -> Void

    @State private var selectedMember: AppUser?

    var body: some View {
        ScrollView {
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
                    Text("\(members.count) membre\(members.count > 1 ? "s" : "")")
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

                // Liste des membres — juste en dessous des actions
                VStack(alignment: .leading, spacing: 10) {
                    Text("Membres")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Pitcha.navy)
                        .padding(.horizontal)

                    VStack(spacing: 8) {
                        ForEach(members) { member in
                            Button {
                                selectedMember = member
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarImage(user: member, size: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(member.pseudo)
                                                .font(.subheadline.weight(.heavy))
                                                .foregroundStyle(Pitcha.navy)
                                            if member.id == team.ownerId {
                                                Image(systemName: "crown.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.yellow)
                                            }
                                        }
                                        Text("Niv. \(member.level) · \(member.overall) OVR")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.white)
                                        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Pitcha.background)
        .sheet(item: $selectedMember) { member in
            PublicProfileSheet(member: member)
        }
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

// MARK: - Classement de l'équipe

struct TeamRankingSheet: View {
    let team: Team
    let members: [AppUser]

    @State private var selectedMember: AppUser?

    private var ranked: [AppUser] {
        members.sorted {
            ($0.totalGoals, $0.xp) > ($1.totalGoals, $1.xp)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Podium top 3
                    if ranked.count >= 3 {
                        HStack(alignment: .bottom, spacing: 10) {
                            // 2e
                            Button { selectedMember = ranked[1] } label: {
                                PodiumMember(user: ranked[1], rank: 2, height: 80)
                            }
                            .buttonStyle(.plain)
                            // 1er
                            Button { selectedMember = ranked[0] } label: {
                                PodiumMember(user: ranked[0], rank: 1, height: 110)
                            }
                            .buttonStyle(.plain)
                            // 3e
                            Button { selectedMember = ranked[2] } label: {
                                PodiumMember(user: ranked[2], rank: 3, height: 60)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    // Liste complète
                    LazyVStack(spacing: 10) {
                        ForEach(Array(ranked.enumerated()), id: \.element.id) { index, player in
                            Button { selectedMember = player } label: {
                                TeamRankRow(player: player, rank: index + 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .background(Pitcha.background)
            .navigationTitle("Classement · \(team.name)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $selectedMember) { member in
            PublicProfileSheet(member: member)
        }
    }
}

// MARK: - Marche du podium

struct PodiumMember: View {
    let user: AppUser
    let rank: Int
    let height: CGFloat

    private var medalColor: Color {
        switch rank {
        case 1: return Color(hex: "FFD700")
        case 2: return Color(white: 0.72)
        default: return Color(hex: "CD7F32")
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            // Initiales
            ZStack {
                AvatarImage(user: user, size: 50)
                // Médaille
                ZStack {
                    Circle().fill(medalColor).frame(width: 20, height: 20)
                    Text("\(rank)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white)
                }
                .offset(x: 18, y: -18)
            }

            Text(user.pseudo)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Pitcha.navy)
                .lineLimit(1)

            Text("\(user.totalGoals) ⚽️")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            // Marche du podium
            RoundedRectangle(cornerRadius: 10)
                .fill(medalColor.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(medalColor.opacity(0.5), lineWidth: 1.5)
                )
                .frame(height: height)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Ligne du classement

struct TeamRankRow: View {
    let player: AppUser
    let rank: Int

    private var medalColor: Color? {
        switch rank {
        case 1: return Color(hex: "FFD700")
        case 2: return Color(white: 0.72)
        case 3: return Color(hex: "CD7F32")
        default: return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Rang
            Group {
                if let color = medalColor {
                    ZStack {
                        Circle().fill(color.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Text("\(rank)")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(color)
                    }
                } else {
                    Text("\(rank)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.secondary)
                        .frame(width: 32)
                }
            }

            // Avatar
            AvatarImage(user: player, size: 40)

            // Infos
            VStack(alignment: .leading, spacing: 2) {
                Text(player.pseudo)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Pitcha.navy)
                Text("Niv. \(player.level) · \(player.overall) général")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            // Stats clés
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text("\(player.totalGoals)")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Pitcha.tealDark)
                    Text("⚽️").font(.caption)
                }
                Text("\(player.totalWins)V · \(player.totalLosses)D")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        )
    }
}
