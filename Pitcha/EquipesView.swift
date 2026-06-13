import SwiftUI

struct EquipesView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var teamsViewModel = EquipesViewModel()
    @StateObject private var friendsViewModel = FriendsViewModel()
    @State private var showCreateSheet = false
    @State private var showAddFriendSheet = false
    @State private var selectedTab = 0   // 0 = Équipes, 1 = Amis
    @State private var searchText = ""

    private var filteredTeams: [Team] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return teamsViewModel.teams }
        return teamsViewModel.teams.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                    // Tabs Équipes / Amis avec soulignement
                    HStack(spacing: 0) {
                        TopTab(label: "Équipes", isSelected: selectedTab == 0) { selectedTab = 0 }
                        TopTab(label: "Amis", isSelected: selectedTab == 1) { selectedTab = 1 }
                    }
                    .padding(.top, 8)

                    if selectedTab == 0 {
                    teamsTab
                } else {
                    FriendsTab(viewModel: friendsViewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PitchaBackground())
            .overlay(alignment: .bottomTrailing) {
                // En overlay sur la zone safe : toujours AU-DESSUS de la tab bar
                PitchaFAB {
                    if selectedTab == 0 {
                        showCreateSheet = true
                    } else {
                        showAddFriendSheet = true
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 80)
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateTeamSheet(viewModel: teamsViewModel)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAddFriendSheet) {
                AddFriendSheet(viewModel: friendsViewModel)
                    .presentationDetents([.height(380)])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                teamsViewModel.listen(uid: session.user?.id)
                friendsViewModel.listen(friendUids: session.user?.friends ?? [])
            }
            .onChange(of: session.user?.id) { _, newUid in
                teamsViewModel.listen(uid: newUid)
            }
            .onChange(of: session.user?.friends) { _, newFriends in
                friendsViewModel.listen(friendUids: newFriends ?? [])
            }
            .onChange(of: session.user?.friendRequests) { _, newRequests in
                Task { await friendsViewModel.loadRequests(uids: newRequests ?? []) }
            }
            .task {
                await friendsViewModel.loadRequests(uids: session.user?.incomingRequests ?? [])
            }
        }
    }

    // MARK: - Onglet Équipes

    @ViewBuilder
    private var teamsTab: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Rechercher une équipe...", text: $searchText)
                .autocorrectionDisabled()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.05)))
        .padding(.horizontal)

        if filteredTeams.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "person.3")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(searchText.isEmpty ? "Aucune équipe" : "Aucun résultat")
                    .font(.headline)
                if searchText.isEmpty {
                    Text("Crée ton équipe et invite tes potes !")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredTeams) { team in
                        NavigationLink {
                            TeamDetailView(team: team)
                        } label: {
                            TeamRow(team: team, isOwner: team.ownerId == session.user?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 90)
            }
        }
    }
}

// MARK: - Onglet Amis

struct FriendsTab: View {
    @ObservedObject var viewModel: FriendsViewModel
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Demandes reçues : à accepter ou refuser
                if !viewModel.requests.isEmpty {
                    HStack {
                        Text("Demandes reçues (\(viewModel.requests.count))")
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(Pitcha.navy)
                        Spacer()
                    }
                    ForEach(viewModel.requests) { requester in
                        FriendRequestRow(requester: requester, viewModel: viewModel)
                    }
                    Divider().padding(.vertical, 4)
                }

                if viewModel.friends.isEmpty && viewModel.requests.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.badge.plus")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Aucun ami pour l'instant")
                            .font(.headline)
                        Text("Ajoute des joueurs avec le bouton +")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 80)
                } else {
                    // Tap sur un ami = ouvrir la discussion privée
                    ForEach(viewModel.friends) { friend in
                        NavigationLink {
                            FriendChatView(friend: friend)
                        } label: {
                            FriendRow(friend: friend)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await viewModel.removeFriend(friend, myUid: session.user?.id) }
                            } label: {
                                Label("Retirer de mes amis", systemImage: "person.badge.minus")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 90)
        }
    }
}

// MARK: - Ligne de demande d'ami reçue

struct FriendRequestRow: View {
    let requester: AppUser
    @ObservedObject var viewModel: FriendsViewModel
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(text: requester.pseudo, size: 46, cornerStyle: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(requester.pseudo)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Pitcha.navy)
                Text("veut devenir ton ami")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await viewModel.decline(requester, myUid: session.user?.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.black.opacity(0.06)))
            }

            Button {
                Task { await viewModel.accept(requester, myUid: session.user?.id) }
            } label: {
                Image(systemName: "checkmark")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Pitcha.gradient))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Pitcha.teal.opacity(0.4), lineWidth: 1.5)
        )
    }
}

struct FriendRow: View {
    let friend: AppUser

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                InitialsAvatar(text: friend.pseudo, size: 52, cornerStyle: .circle)
                Circle()
                    .fill(friend.isOnline ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(friend.pseudo)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Pitcha.navy)
                Text(friend.isOnline ? "En ligne" : "Hors ligne")
                    .font(.subheadline)
                    .foregroundStyle(friend.isOnline ? .green : .secondary)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("\(friend.overall)")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Pitcha.tealDark)
                Text("OVR")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        )
    }
}

// MARK: - Sheet ajout d'ami

struct AddFriendSheet: View {
    @ObservedObject var viewModel: FriendsViewModel
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var pseudo = ""

    var body: some View {
        VStack(spacing: 18) {
            Text("Ajouter un ami")
                .font(.title3.bold())
                .padding(.top, 24)

            HStack(spacing: 10) {
                PitchaTextField(icon: "person.fill", placeholder: "Pseudo exact", text: $pseudo)
                    .textInputAutocapitalization(.never)

                Button {
                    Task {
                        await viewModel.search(
                            pseudo: pseudo,
                            myUid: session.user?.id,
                            currentFriends: session.user?.friends ?? []
                        )
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Pitcha.gradient))
                }
            }
            .padding(.horizontal)

            if viewModel.isWorking {
                ProgressView()
            }

            if let message = viewModel.searchMessage {
                Text(message)
                    .font(.footnote.bold())
                    .foregroundStyle(message.contains("✓") ? .green : .secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if let result = viewModel.searchResult {
                HStack(spacing: 14) {
                    InitialsAvatar(text: result.pseudo, size: 48, cornerStyle: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.pseudo)
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(Pitcha.navy)
                        Text("NIV. \(result.level) • OVR \(result.overall)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task {
                            await viewModel.sendRequest(to: result, myUid: session.user?.id)
                        }
                    } label: {
                        Text("Envoyer une demande")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Pitcha.gradient))
                            .foregroundStyle(.white)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.04)))
                .padding(.horizontal)
            }

            Spacer()
        }
        .onDisappear {
            viewModel.searchResult = nil
            viewModel.searchMessage = nil
        }
    }
}

// MARK: - Tab du haut avec soulignement

struct TopTab: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            VStack(spacing: 12) {
                Text(label.uppercased())
                    .font(.subheadline.weight(.heavy))
                    .kerning(2)
                    .foregroundStyle(isSelected ? Pitcha.navy : Color.gray.opacity(0.6))
                Rectangle()
                    .fill(isSelected ? Pitcha.tealDark : Color.gray.opacity(0.2))
                    .frame(height: 3)
            }
        }
    }
}

// MARK: - Ligne équipe

struct TeamRow: View {
    let team: Team
    let isOwner: Bool

    var body: some View {
        HStack(spacing: 14) {
            TeamCrest(team: team, size: 56)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(team.name.uppercased())
                        .font(.headline.weight(.heavy))
                        .kerning(1)
                        .foregroundStyle(Pitcha.navy)
                    if isOwner {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(Pitcha.teal)
                        .frame(width: 7, height: 7)
                    Text("\(team.memberIds.count) membre\(team.memberIds.count > 1 ? "s" : "")")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.05))
                    .frame(width: 42, height: 42)
                Image(systemName: "arrow.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(Pitcha.navy)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.white)
                .shadow(color: .black.opacity(0.06), radius: 10, y: 5)
        )
    }
}

// MARK: - Sheet de création d'équipe (avec sélection d'amis)

struct CreateTeamSheet: View {
    @ObservedObject var viewModel: EquipesViewModel
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var friends: [AppUser] = []
    @State private var selectedFriendIds: Set<String> = []
    @State private var crestIcon = CrestPalette.icons[0]
    @State private var crestColorName = CrestPalette.colors[0].name

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    PitchaTextField(icon: "shield.fill", placeholder: "Nom de l'équipe", text: $name)
                        .padding(.horizontal)
                        .padding(.top, 12)

                    CrestBuilder(name: name, crestIcon: $crestIcon, crestColorName: $crestColorName)
                        .padding(.horizontal)

                    if !friends.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Ajouter des amis (\(selectedFriendIds.count))")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(friends) { friend in
                                Button {
                                    guard let uid = friend.id else { return }
                                    withAnimation(.snappy) {
                                        if selectedFriendIds.contains(uid) {
                                            selectedFriendIds.remove(uid)
                                        } else {
                                            selectedFriendIds.insert(uid)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        InitialsAvatar(text: friend.pseudo, size: 42, cornerStyle: .circle)
                                        Text(friend.pseudo)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(Pitcha.navy)
                                        Spacer()
                                        Image(systemName: friend.id.map { selectedFriendIds.contains($0) } == true
                                              ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(friend.id.map { selectedFriendIds.contains($0) } == true
                                                             ? Pitcha.teal : Color.gray.opacity(0.4))
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)
                                }
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
                            let success = await viewModel.createTeam(
                                name: name,
                                ownerId: session.user?.id,
                                memberIds: Array(selectedFriendIds),
                                crestIcon: crestIcon,
                                crestColorName: crestColorName
                            )
                            if success { dismiss() }
                        }
                    } label: {
                        Group {
                            if viewModel.isWorking {
                                ProgressView().tint(.white)
                            } else {
                                Text("Créer l'équipe").fontWeight(.bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(name.trimmingCharacters(in: .whitespaces).count >= 3
                                      ? AnyShapeStyle(Pitcha.gradient)
                                      : AnyShapeStyle(Color.gray.opacity(0.4)))
                        )
                        .foregroundStyle(.white)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).count < 3 || viewModel.isWorking)
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Nouvelle équipe")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                let uids = session.user?.friends ?? []
                friends = (try? await FirebaseService.shared.fetchUsers(uids: uids)) ?? []
            }
        }
    }
}


// MARK: - Écusson d'équipe

struct TeamCrest: View {
    let team: Team
    var size: CGFloat = 56

    var body: some View {
        if let icon = team.crestIcon {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.32)
                    .fill(
                        LinearGradient(
                            colors: [CrestPalette.color(named: team.crestColorName),
                                     CrestPalette.color(named: team.crestColorName).opacity(0.6)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: size, height: size)
                Image(systemName: icon)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }
        } else {
            InitialsAvatar(text: team.name, size: size)
        }
    }
}

// MARK: - Créateur d'écusson (aperçu live + icônes + couleurs)

struct CrestBuilder: View {
    let name: String
    @Binding var crestIcon: String
    @Binding var crestColorName: String

    private let iconColumns = [GridItem(.adaptive(minimum: 48))]

    var body: some View {
        VStack(spacing: 14) {
            Text("Écusson de l'équipe")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Aperçu live
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: [CrestPalette.color(named: crestColorName),
                                     CrestPalette.color(named: crestColorName).opacity(0.6)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 84, height: 84)
                    .shadow(color: CrestPalette.color(named: crestColorName).opacity(0.4), radius: 8, y: 4)
                VStack(spacing: 2) {
                    Image(systemName: crestIcon)
                        .font(.system(size: 30, weight: .bold))
                    if !name.isEmpty {
                        Text(String(name.prefix(3)).uppercased())
                            .font(.system(size: 11, weight: .heavy))
                            .kerning(1)
                    }
                }
                .foregroundStyle(.white)
            }

            // Icônes
            LazyVGrid(columns: iconColumns, spacing: 10) {
                ForEach(CrestPalette.icons, id: \.self) { icon in
                    Button {
                        withAnimation(.snappy) { crestIcon = icon }
                    } label: {
                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundStyle(crestIcon == icon ? .white : Pitcha.navy)
                            .frame(width: 46, height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(crestIcon == icon ? AnyShapeStyle(Pitcha.gradient) : AnyShapeStyle(Color.black.opacity(0.05)))
                            )
                    }
                }
            }

            // Couleurs
            HStack(spacing: 10) {
                ForEach(CrestPalette.colors, id: \.name) { item in
                    Button {
                        withAnimation(.snappy) { crestColorName = item.name }
                    } label: {
                        Circle()
                            .fill(item.color)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle().strokeBorder(.white, lineWidth: crestColorName == item.name ? 3 : 0)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.04)))
    }
}
