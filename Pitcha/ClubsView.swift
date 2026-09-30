import SwiftUI

// MARK: - Section "Clubs Classé" — affichée en bas de l'onglet Équipes.
// Un club = roster fixe (5 titulaires + 3 remplaçants) utilisé pour
// rejoindre un match Classé. Max 3 clubs par utilisateur.

struct RankedClubsSection: View {
    @EnvironmentObject var session: SessionViewModel
    @State private var clubs: [Club] = []
    @State private var isLoading = true
    @State private var showCreateClub = false

    private var canCreateAnother: Bool {
        (session.user?.clubIdsValue.count ?? 0) < Club.maxClubsPerUser
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "shield.fill")
                        .foregroundStyle(Color(hex: "F2C740"))
                    Text("CLUBS CLASSÉ")
                        .font(.caption.weight(.heavy))
                        .kerning(1.2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(clubs.count)/\(Club.maxClubsPerUser)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text("Un club (5 titulaires + 3 remplaçants) est nécessaire pour créer ou rejoindre un match Classé.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                ForEach(clubs) { club in
                    NavigationLink {
                        ClubDetailView(clubId: club.id ?? "")
                    } label: {
                        ClubRow(club: club, isCaptain: club.captainId == session.user?.id)
                    }
                    .buttonStyle(.plain)
                }

                if canCreateAnother {
                    Button {
                        showCreateClub = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                            Text("Créer un club")
                                .font(.subheadline.weight(.bold))
                            Spacer()
                        }
                        .foregroundStyle(Pitcha.teal)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Pitcha.teal.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        )
                    }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showCreateClub) {
            ClubCreateSheet(onCreated: { Task { await load() } })
        }
    }

    private func load() async {
        guard let uids = session.user?.clubIdsValue, !uids.isEmpty else {
            clubs = []
            isLoading = false
            return
        }
        isLoading = true
        clubs = (try? await FirebaseService.shared.fetchMyClubs(clubIds: uids)) ?? []
        isLoading = false
    }
}

// MARK: - Ligne club (aperçu, dans la section)

struct ClubRow: View {
    let club: Club
    let isCaptain: Bool
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(CrestPalette.color(named: club.crestColorName).gradient)
                    .frame(width: 48, height: 48)
                Image(systemName: club.crestIcon ?? "shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(club.name)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Pitcha.navy)
                    if isCaptain {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: "F2C740"))
                    }
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(club.isReadyForRanked ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(club.isReadyForRanked
                         ? "Prêt pour le Classé"
                         : "\(Club.maxStarters - club.starterIds.count) titulaire(s) manquant(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            let unread = club.unreadCount(for: session.user?.id)
            if unread > 0 {
                Text("\(min(unread, 99))")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Circle().fill(Color.red))
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
    }
}

// MARK: - Création d'un club

struct ClubCreateSheet: View {
    let onCreated: () -> Void
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedIcon = CrestPalette.icons[0]
    @State private var selectedColorName = CrestPalette.colors[0].name
    @State private var isWorking = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(CrestPalette.color(named: selectedColorName).gradient)
                            .frame(width: 96, height: 96)
                        Image(systemName: selectedIcon)
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 12)

                    PitchaTextField(icon: "shield.fill", placeholder: "Nom du club", text: $name)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Écusson").font(.caption.weight(.heavy)).foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(CrestPalette.icons, id: \.self) { icon in
                                Button { selectedIcon = icon } label: {
                                    Image(systemName: icon)
                                        .font(.title3)
                                        .foregroundStyle(selectedIcon == icon ? .white : Pitcha.navy)
                                        .frame(width: 50, height: 50)
                                        .background(
                                            Circle().fill(selectedIcon == icon ? AnyShapeStyle(Pitcha.gradient) : AnyShapeStyle(Color.black.opacity(0.06)))
                                        )
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Couleur").font(.caption.weight(.heavy)).foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(CrestPalette.colors, id: \.name) { entry in
                                Button { selectedColorName = entry.name } label: {
                                    Circle()
                                        .fill(entry.color)
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Circle().strokeBorder(.white, lineWidth: selectedColorName == entry.name ? 3 : 0)
                                        )
                                        .overlay(
                                            Circle().strokeBorder(Pitcha.navy.opacity(selectedColorName == entry.name ? 0.3 : 0), lineWidth: 1)
                                        )
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }

                    Button {
                        create()
                    } label: {
                        Group {
                            if isWorking { ProgressView().tint(.white) }
                            else { Text("Créer le club").fontWeight(.bold) }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 16).fill(name.trimmingCharacters(in: .whitespaces).count >= 3 ? AnyShapeStyle(Pitcha.gradient) : AnyShapeStyle(Color.gray.opacity(0.3))))
                        .foregroundStyle(.white)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).count < 3 || isWorking)
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Nouveau club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Annuler") { dismiss() } }
            }
        }
    }

    private func create() {
        guard let user = session.user else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await FirebaseService.shared.createClub(
                    name: name, crestIcon: selectedIcon, crestColorName: selectedColorName, captain: user
                )
                onCreated()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

// MARK: - Détail d'un club : gestion du roster

struct ClubDetailView: View {
    let clubId: String
    @EnvironmentObject var session: SessionViewModel
    @EnvironmentObject var network: NetworkMonitor
    @EnvironmentObject var tabBarVisibility: TabBarVisibility
    @Environment(\.dismiss) private var dismiss

    @State private var club: Club?
    @State private var messages: [ChatMessage] = []
    @State private var messageText = ""
    @FocusState private var isMessageFieldFocused: Bool
    @State private var showClubInfo = false
    @State private var showRanking = false
    @State private var showHighlightInfo = false
    @State private var actionErrorMessage: String?

    private var isCaptain: Bool { club?.captainId == session.user?.id }

    private func sendCurrentMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""
        Task { try? await FirebaseService.shared.sendClubMessage(clubId: clubId, sender: session.user, text: text) }
        isMessageFieldFocused = true
    }

    // Barre d'actions : uniquement Classement et Highlight — organiser un
    // match Classé se fait depuis le "+" de l'onglet Matchs (choix du club),
    // pas depuis ici.
    private var actionsBar: some View {
        HStack(spacing: 12) {
            Spacer()
            TeamActionChip(icon: "video.fill", label: "Highlight") {
                showHighlightInfo = true
            }
            TeamActionChip(icon: "list.number", label: "Classement") {
                showRanking = true
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

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
                    guard let sender = session.user else { return }
                    Task { try? await FirebaseService.shared.sendPhotoClubMessage(clubId: clubId, sender: sender, photoData: data) }
                }
                .disabled(!network.isConnected)
                VoiceRecordButton { fileURL, duration in
                    guard let sender = session.user else { return }
                    Task { try? await FirebaseService.shared.sendVoiceClubMessage(clubId: clubId, sender: sender, fileURL: fileURL, duration: duration) }
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
                    if value.translation.height > 15 { isMessageFieldFocused = false }
                }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if !network.isConnected { OfflineChatBanner() }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                isMine: message.senderId == session.user?.id,
                                context: "club",
                                contextId: clubId
                            )
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let lastId = messages.last?.id {
                        withAnimation(.snappy) { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
            }

            actionsBar
            inputBar
        }
        .background(PitchaBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    showClubInfo = true
                } label: {
                    HStack(spacing: 5) {
                        Text(club?.name ?? "Club").font(.headline.weight(.heavy))
                        Image(systemName: "chevron.down").font(.caption2.bold())
                    }
                    .foregroundStyle(Pitcha.navy)
                }
            }
        }
        .sheet(isPresented: $showClubInfo) {
            if let club {
                ClubInfoSheet(club: club, clubId: clubId, isCaptain: isCaptain, onDissolved: { dismiss() })
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showRanking) {
            ClubRankingSheet(club: club)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Bientôt disponible 📹", isPresented: $showHighlightInfo) {
            Button("OK") {}
        } message: {
            Text("Les highlights arrivent dans une prochaine version : tu pourras partager tes plus belles actions avec ton club.")
        }
        .alert("Erreur", isPresented: .init(get: { actionErrorMessage != nil }, set: { if !$0 { actionErrorMessage = nil } })) {
            Button("OK") { actionErrorMessage = nil }
        } message: {
            Text(actionErrorMessage ?? "")
        }
        .task {
            _ = FirebaseService.shared.listenClub(clubId: clubId) { updated in
                Task { @MainActor in club = updated }
            }
            _ = FirebaseService.shared.listenClubMessages(clubId: clubId) { updated in
                Task { @MainActor in messages = updated }
            }
        }
        .onAppear {
            tabBarVisibility.isHidden = true
            if let uid = session.user?.id {
                Task {
                    await FirebaseService.shared.markClubMessagesRead(clubId: clubId, uid: uid)
                    await session.refreshUnreadCount(uid: uid)
                }
            }
        }
        .onDisappear {
            tabBarVisibility.isHidden = false
        }
    }
}

// MARK: - Infos du club (roster, gestion) — ouverte en tapant le nom du club

struct ClubInfoSheet: View {
    let club: Club
    let clubId: String
    let isCaptain: Bool
    let onDissolved: () -> Void

    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showInvite = false
    @State private var inviteAsStarter = true
    @State private var showDeleteConfirm = false
    @State private var showRenameAlert = false
    @State private var newName = ""
    @State private var actionErrorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 26)
                            .fill(CrestPalette.color(named: club.crestColorName).gradient)
                            .frame(height: 110)
                        HStack(spacing: 14) {
                            Image(systemName: club.crestIcon ?? "shield.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.white)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(club.name)
                                    .font(.title3.weight(.heavy))
                                    .foregroundStyle(.white)
                                Text(club.isReadyForRanked ? "Prêt pour le Classé" : "Roster incomplet")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    rosterSection(title: starterTitle(club: club), uids: club.starterIds, isStarterList: true, club: club)
                    rosterSection(title: substituteTitle(club: club), uids: club.substituteIds, isStarterList: false, club: club)

                    if isCaptain {
                        Button {
                            newName = club.name
                            showRenameAlert = true
                        } label: {
                            Text("Renommer le club")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Pitcha.tealDark)
                        }
                        .padding(.top, 8)

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Text("Dissoudre le club")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.bottom, 40)
                .alert("Renommer le club", isPresented: $showRenameAlert) {
                    TextField("Nom du club", text: $newName)
                    Button("Annuler", role: .cancel) {}
                    Button("Renommer") {
                        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        Task {
                            do {
                                try await FirebaseService.shared.renameClub(clubId: clubId, newName: trimmed)
                            } catch {
                                actionErrorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
            .background(Pitcha.background)
            .navigationTitle(club.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Fermer") { dismiss() } }
                if isCaptain {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { inviteAsStarter = true; showInvite = true } label: {
                                Label("Ajouter un titulaire", systemImage: "person.fill.badge.plus")
                            }
                            Button { inviteAsStarter = false; showInvite = true } label: {
                                Label("Ajouter un remplaçant", systemImage: "person.badge.plus")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showInvite) {
                ClubInvitePlayerSheet(clubId: clubId, asStarter: inviteAsStarter)
            }
            .confirmationDialog("Dissoudre ce club ?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Dissoudre définitivement", role: .destructive) {
                    Task {
                        do {
                            try await FirebaseService.shared.deleteClub(clubId: clubId)
                            dismiss()
                            onDissolved()
                        } catch {
                            actionErrorMessage = error.localizedDescription
                        }
                    }
                }
            } message: {
                Text("Cette action est irréversible. Le club sera retiré de tous les joueurs concernés.")
            }
            .alert("Erreur", isPresented: .init(get: { actionErrorMessage != nil }, set: { if !$0 { actionErrorMessage = nil } })) {
                Button("OK") { actionErrorMessage = nil }
            } message: {
                Text(actionErrorMessage ?? "")
            }
        }
    }

    private func starterTitle(club: Club) -> String {
        "Titulaires (\(club.starterIds.count)/\(Club.maxStarters))"
    }

    private func substituteTitle(club: Club) -> String {
        "Remplaçants (\(club.substituteIds.count)/\(Club.maxSubstitutes))"
    }

    private func rosterSection(title: String, uids: [String], isStarterList: Bool, club: Club) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            rosterSectionHeader(title: title)
            rosterSectionContent(uids: uids, isStarterList: isStarterList, club: club)
        }
    }

    private func rosterSectionHeader(title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.heavy))
            .kerning(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
    }

    @ViewBuilder
    private func rosterSectionContent(uids: [String], isStarterList: Bool, club: Club) -> some View {
        if uids.isEmpty {
            Text("Aucun joueur pour l'instant")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        } else {
            VStack(spacing: 8) {
                ForEach(uids, id: \.self) { uid in
                    memberRow(uid: uid, isStarterList: isStarterList, club: club)
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func memberRow(uid: String, isStarterList: Bool, club: Club) -> some View {
        let isCaptainRow: Bool = (uid == club.captainId)
        let isSelfRow: Bool = (uid == session.user?.id)
        let canManageRow: Bool = isCaptain && !isCaptainRow
        let moveLabelText: String = isStarterList ? "Passer remplaçant" : "Passer titulaire"

        ClubMemberRow(
            uid: uid,
            isCaptainRow: isCaptainRow,
            isSelf: isSelfRow,
            canManage: canManageRow,
            onRemove: { removeMember(uid: uid) },
            onMove: { moveMember(uid: uid, isStarterList: isStarterList) },
            onLeave: { leaveClubAsMember() },
            moveLabel: moveLabelText
        )
    }

    private func removeMember(uid: String) {
        Task {
            do {
                try await FirebaseService.shared.removeFromClubRoster(clubId: clubId, uid: uid)
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func moveMember(uid: String, isStarterList: Bool) {
        Task {
            do {
                try await FirebaseService.shared.moveClubRosterSlot(clubId: clubId, uid: uid, toStarter: !isStarterList)
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func leaveClubAsMember() {
        Task {
            do {
                try await FirebaseService.shared.leaveClub(clubId: clubId)
                dismiss()
                onDissolved()
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Classement du club (par PL/division, pas goals/xp)

struct ClubRankingSheet: View {
    let club: Club?
    @State private var members: [AppUser] = []
    @State private var isLoading = true

    private var ranked: [AppUser] {
        members.sorted {
            ($0.rankedPLValue + ($0.rankedDivisionEnum?.order ?? -1) * 100) >
            ($1.rankedPLValue + ($1.rankedDivisionEnum?.order ?? -1) * 100)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            if ranked.count >= 3 {
                                HStack(alignment: .bottom, spacing: 10) {
                                    PodiumMember(user: ranked[1], rank: 2, height: 80)
                                    PodiumMember(user: ranked[0], rank: 1, height: 110)
                                    PodiumMember(user: ranked[2], rank: 3, height: 60)
                                }
                                .padding(.horizontal)
                                .padding(.top, 8)
                            }
                            LazyVStack(spacing: 10) {
                                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, player in
                                    TeamRankRow(player: player, rank: index + 1)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
            .background(Pitcha.background)
            .navigationTitle("Classement · \(club?.name ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                guard let club else { isLoading = false; return }
                let uids = club.starterIds + club.substituteIds
                members = (try? await FirebaseService.shared.fetchUsers(uids: uids)) ?? []
                isLoading = false
            }
        }
    }
}

// MARK: - Ligne membre du roster (résout le pseudo/avatar depuis l'uid)
//
// L'avatar + le pseudo sont maintenant tappables : ça ouvre le même
// PublicProfileSheet (lecture seule, avec bouton "Ajouter en ami") que
// dans les équipes — sans les sous-stats ni l'OVR, plus utilisés.

struct ClubMemberRow: View {
    let uid: String
    let isCaptainRow: Bool
    let isSelf: Bool
    let canManage: Bool
    let onRemove: () -> Void
    let onMove: () -> Void
    let onLeave: () -> Void
    let moveLabel: String

    @State private var user: AppUser?
    @State private var showLeaveConfirm = false
    @State private var showProfile = false

    var body: some View {
        HStack(spacing: 12) {
            if let user {
                Button {
                    showProfile = true
                } label: {
                    HStack(spacing: 12) {
                        AvatarImage(user: user, size: 38)
                        Text(user.pseudo).font(.subheadline.weight(.bold))
                    }
                }
                .buttonStyle(.plain)
            } else {
                Circle().fill(Color.gray.opacity(0.15)).frame(width: 38, height: 38)
                Text("...").font(.subheadline).foregroundStyle(.secondary)
            }
            if isCaptainRow {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "F2C740"))
            }
            Spacer()
            if canManage {
                Menu {
                    Button(moveLabel, systemImage: "arrow.left.arrow.right") { onMove() }
                    Button("Retirer du club", systemImage: "person.fill.xmark", role: .destructive) { onRemove() }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            } else if isSelf && !isCaptainRow {
                // Un membre (pas le capitaine) peut se retirer lui-même.
                Button {
                    showLeaveConfirm = true
                } label: {
                    Text("Quitter")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.red.opacity(0.1)))
                }
                .confirmationDialog("Quitter ce club ?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
                    Button("Quitter", role: .destructive) { onLeave() }
                } message: {
                    Text("Tu pourras rejoindre un autre club à la place.")
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
        .task {
            let uids = [uid]
            user = (try? await FirebaseService.shared.fetchUsers(uids: uids))?.first
        }
        .sheet(isPresented: $showProfile) {
            if let user {
                PublicProfileSheet(member: user)
            }
        }
    }
}

// MARK: - Inviter un joueur dans le roster (par pseudo)

struct ClubInvitePlayerSheet: View {
    let clubId: String
    let asStarter: Bool
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var friends: [AppUser] = []
    @State private var isLoading = true
    @State private var addingUid: String?
    @State private var resultMessage: String?

    private var filteredFriends: [AppUser] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return friends }
        return friends.filter { $0.pseudo.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text(asStarter ? "Ajoute un titulaire depuis tes amis" : "Ajoute un remplaçant depuis tes amis")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.top, 12)

                // Barre de recherche
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Rechercher un ami...", text: $searchText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.05)))
                .padding(.horizontal)

                if let resultMessage {
                    Text(resultMessage)
                        .font(.footnote)
                        .foregroundStyle(resultMessage.contains("✓") ? .green : .red)
                }

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if friends.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("Tu n'as pas encore d'amis à ajouter.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredFriends.isEmpty {
                    Text("Aucun ami ne correspond à cette recherche.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 30)
                    Spacer()
                } else {
                    // Liste d'amis en bas, sélectionnables — plus d'ajout libre par pseudo.
                    List(filteredFriends) { friend in
                        HStack(spacing: 12) {
                            AvatarImage(user: friend, size: 40)
                            Text(friend.pseudo).font(.subheadline.weight(.bold))
                            Spacer()
                            if addingUid == friend.id {
                                ProgressView()
                            } else {
                                Button {
                                    add(friend)
                                } label: {
                                    Text("Ajouter")
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
            .navigationTitle(asStarter ? "Ajouter un titulaire" : "Ajouter un remplaçant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } }
            }
            .task {
                guard let uids = session.user?.friends, !uids.isEmpty else { isLoading = false; return }
                friends = (try? await FirebaseService.shared.fetchUsers(uids: uids)) ?? []
                isLoading = false
            }
        }
    }

    private func add(_ friend: AppUser) {
        addingUid = friend.id
        resultMessage = nil
        Task {
            do {
                try await FirebaseService.shared.addToClubRoster(clubId: clubId, friend: friend, asStarter: asStarter)
                resultMessage = "\(friend.pseudo) a rejoint le club ✓"
            } catch {
                resultMessage = error.localizedDescription
            }
            addingUid = nil
        }
    }
}
