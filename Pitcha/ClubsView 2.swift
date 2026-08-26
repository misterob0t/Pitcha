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
    @State private var club: Club?
    @State private var listener: Any?
    @State private var showInvite = false
    @State private var inviteAsStarter = true
    @State private var showDeleteConfirm = false
    @State private var actionErrorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var isCaptain: Bool { club?.captainId == session.user?.id }

    var body: some View {
        ScrollView {
            if let club {
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
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Text("Dissoudre le club")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.red)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.bottom, 40)
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .background(PitchaBackground())
        .navigationTitle(club?.name ?? "Club")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
            if let club {
                ClubInvitePlayerSheet(clubId: club.id ?? "", asStarter: inviteAsStarter)
            }
        }
        .confirmationDialog("Dissoudre ce club ?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Dissoudre définitivement", role: .destructive) {
                Task {
                    do {
                        try await FirebaseService.shared.deleteClub(clubId: clubId)
                        dismiss()
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
        .task {
            _ = FirebaseService.shared.listenClub(clubId: clubId) { updated in
                Task { @MainActor in club = updated }
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

    // Extraite de rosterSection : le compilateur Swift n'arrivait plus à
    // type-checker l'expression quand tout était inline dans le ForEach
    // (trop de fermetures/comparaisons imbriquées d'un coup).
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
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Ligne membre du roster (résout le pseudo/avatar depuis l'uid)

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

    var body: some View {
        HStack(spacing: 12) {
            if let user {
                AvatarImage(user: user, size: 38)
                Text(user.pseudo).font(.subheadline.weight(.bold))
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
