import SwiftUI

struct TeamDetailView: View {
    let team: Team
    @EnvironmentObject var session: SessionViewModel
    @EnvironmentObject var tabBarVisibility: TabBarVisibility
    @EnvironmentObject var network: NetworkMonitor
    @StateObject private var viewModel = TeamDetailViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var messageText = ""
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

    // Barre de saisie du chat
    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message...", text: $messageText)
                .disabled(!network.isConnected)
                .submitLabel(.send)
                .onSubmit { sendCurrentMessage() }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Button { sendCurrentMessage() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle((messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !network.isConnected) ? .gray : Pitcha.teal)
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !network.isConnected)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.teamMatches.isEmpty {
                if viewModel.teamMatches.count == 1, let onlyMatch = viewModel.teamMatches.first {
                    // Un seul match : occupe toute la largeur au lieu d'être
                    // collé à gauche comme dans un carrousel à un seul élément.
                    TeamMatchCard(match: onlyMatch, team: team, viewModel: viewModel, fullWidth: true)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                } else {
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
                memberCount: viewModel.members.count,
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

// MARK: - Bulle de message

struct MessageBubble: View {
    let message: ChatMessage
    let isMine: Bool
    /// Contexte d'où vient ce message, pour le signalement ("team" ou "dm").
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
        HStack(alignment: .bottom, spacing: 0) {
            if isMine { Spacer(minLength: 48) }

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
                Text(isFromBlockedUser ? "🚫 Message masqué (utilisateur bloqué)" : message.text)
                    .italic(isFromBlockedUser)
                    .frame(maxWidth: 260, alignment: isMine ? .trailing : .leading)
                    .multilineTextAlignment(isMine ? .trailing : .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(isFromBlockedUser ? Color.gray.opacity(0.15) : (isMine ? Color.teal : Color(.secondarySystemBackground)))
                    .foregroundStyle(isFromBlockedUser ? AnyShapeStyle(.secondary) : (isMine ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary)))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                Text(timeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !isMine { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 4)
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
    /// true quand c'est l'unique match affiché (hors carrousel) : occupe
    /// alors toute la largeur disponible au lieu d'une largeur fixe.
    var fullWidth: Bool = false
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
        .frame(maxWidth: fullWidth ? .infinity : 320)
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


// MARK: - Fiche équipe (tap sur le nom)

struct TeamInfoSheet: View {
    let team: Team
    let isOwner: Bool
    let memberCount: Int
    let members: [AppUser]
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

            // Liste des membres du groupe
            VStack(alignment: .leading, spacing: 10) {
                Text("Membres")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Pitcha.navy)
                    .padding(.horizontal, 20)

                if members.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(members) { member in
                                MemberRow(member: member, isOwner: member.id == team.ownerId)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .background(Pitcha.background)
    }
}

// MARK: - Ligne membre (avatar + pseudo + badge capitaine)

struct MemberRow: View {
    let member: AppUser
    let isOwner: Bool

    var body: some View {
        HStack(spacing: 12) {
            AvatarImage(user: member, size: 40)

            Text(member.pseudo)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Pitcha.navy)
                .lineLimit(1)

            if isOwner {
                HStack(spacing: 3) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("CAPITAINE")
                        .font(.system(size: 9, weight: .heavy))
                        .kerning(0.4)
                }
                .foregroundStyle(Pitcha.gold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Pitcha.gold.opacity(0.12)))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white)
        )
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
                            PodiumMember(user: ranked[1], rank: 2, height: 80)
                            // 1er
                            PodiumMember(user: ranked[0], rank: 1, height: 110)
                            // 3e
                            PodiumMember(user: ranked[2], rank: 3, height: 60)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    // Liste complète
                    LazyVStack(spacing: 10) {
                        ForEach(Array(ranked.enumerated()), id: \.element.id) { index, player in
                            TeamRankRow(player: player, rank: index + 1)
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
