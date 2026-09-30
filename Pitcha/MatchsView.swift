import SwiftUI

struct MatchsView: View {
    @EnvironmentObject var session: SessionViewModel
    @EnvironmentObject var router: TabRouter
    @EnvironmentObject var network: NetworkMonitor
    @StateObject private var viewModel = MatchsViewModel()
    @State private var showCreateSheet = false

    private var visibleMatches: [Match] {
        let dismissed = session.user?.dismissedMatches ?? []
        return viewModel.filteredMatches.filter { match in
            guard let id = match.id else { return true }
            return !dismissed.contains(id)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            headerRow
            daysStrip

            MyUpcomingMatchesBanner(matches: viewModel.myUpcomingMatches) { match in
                viewModel.selectedDate = Calendar.current.startOfDay(for: match.date)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            contentBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PitchaBackground())
        .overlay(alignment: .bottom) { bottomOverlay }
        .sheet(isPresented: $showCreateSheet) {
            CreateMatchView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.startAutoRefresh(uid: session.user?.id)
            viewModel.applyDefaultLocation(from: session.user)
        }
        .onDisappear { viewModel.stopAutoRefresh() }
    }

    // MARK: - Header : Publics/Privés/Tournois + filtre de zone

    private var headerRow: some View {
        HStack {
            visibilityPills
            Spacer()
            LocationFilterButton(viewModel: viewModel)
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }

    private var visibilityPills: some View {
        HStack(spacing: 8) {
            ForEach(MatchVisibility.allCases, id: \.self) { visibility in
                let fill: AnyShapeStyle = visibility == .tournois
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [Pitcha.gold, Color(hex: "B8860B")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                      )
                    : AnyShapeStyle(Pitcha.gradient)

                PillButton(
                    label: visibility.rawValue,
                    isSelected: viewModel.visibility == visibility,
                    selectedFill: fill,
                    shimmer: visibility == .tournois
                ) {
                    withAnimation(.snappy) { viewModel.visibility = visibility }
                }
            }
        }
    }

    private var daysStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.upcomingDays, id: \.self) { day in
                    DayChip(date: day, isSelected: viewModel.isSelected(day)) {
                        viewModel.selectedDate = day
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Contenu : liste, état vide, ou placeholder Tournois

    @ViewBuilder
    private var contentBody: some View {
        if viewModel.visibility == .tournois {
            Spacer()
            TournoisComingSoonView()
            Spacer()
            Spacer()
        } else if visibleMatches.isEmpty {
            Spacer()
            EmptyMatchesView()
            Spacer()
            Spacer()
        } else {
            matchesList
        }
    }

    private var matchesList: some View {
        VStack(spacing: 12) {
            ForEach(visibleMatches) { match in
                MatchCard(match: match, viewModel: viewModel)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 90)
    }

    private var bottomOverlay: some View {
        HStack {
            Button {
                router.goToCoins()
            } label: {
                CoinsPill(coins: session.user?.coins ?? 0)
            }
            Spacer()
            PitchaFAB { showCreateSheet = true }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
    }
}

// MARK: - Chip de jour

struct DayChip: View {
    let date: Date
    let isSelected: Bool
    let action: () -> Void

    private var weekdayText: String {
        // Liste fixe plutôt que le DateFormatter "EEE" : le format abrégé
        // français inclut déjà un point ("lun."), qu'on rajoutait par-dessus
        // par erreur -> "LUN.." affiché. Ici, toujours exactement 3 lettres.
        let days = ["DIM", "LUN", "MAR", "MER", "JEU", "VEN", "SAM"]
        let weekday = Calendar.current.component(.weekday, from: date) // 1 = dimanche
        return days[weekday - 1]
    }

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: date))"
    }

    var body: some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            VStack(spacing: 4) {
                Text(weekdayText)
                    .font(.system(size: 11, weight: .heavy))
                    .kerning(1)
                    .opacity(isSelected ? 0.9 : 0.5)
                Text(dayNumber)
                    .font(.system(size: 26, weight: .black, design: .rounded))
            }
            .foregroundStyle(isSelected ? .white : Pitcha.navy)
            .frame(width: 68, height: 76)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? AnyShapeStyle(Pitcha.gradient) : AnyShapeStyle(Color.white))
                    .shadow(color: .black.opacity(isSelected ? 0.12 : 0.04), radius: 4, y: 2)
            )
        }
    }
}

// MARK: - État vide

struct EmptyMatchesView: View {
    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: -8) {
                Text("AUCUN")
                    .font(.system(size: 52, weight: .black))
                    .foregroundStyle(Color.gray.opacity(0.3))
                Text("MATCH")
                    .font(.system(size: 60, weight: .black))
                    .foregroundStyle(Pitcha.navy)
            }

            Rectangle()
                .fill(Pitcha.mint)
                .frame(width: 90, height: 4)
                .clipShape(Capsule())

            Text("Aucun match prévu ce jour")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
    }
}

// MARK: - Placeholder Tournois (fonctionnalité à venir)

struct TournoisComingSoonView: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Pitcha.gold.opacity(0.25), Pitcha.gold.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)

                Image(systemName: "trophy.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Pitcha.gold)
            }

            VStack(spacing: 6) {
                Text("Tournois")
                    .font(.title2.weight(.black))
                    .foregroundStyle(Pitcha.navy)

                Text("Bientôt, retrouve ici les tournois organisés et rejoins-les directement depuis l'app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Text("À venir")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Pitcha.navy.opacity(0.85)))
                .padding(.top, 4)
        }
    }
}

// MARK: - Carte de match (carré heure à gauche : vert = Foot, rouge = Five)

struct MatchCard: View {
    let match: Match
    @EnvironmentObject var session: SessionViewModel
    @EnvironmentObject var network: NetworkMonitor
    @ObservedObject var viewModel: MatchsViewModel

    @State private var showJoinConfirm = false
    @State private var showClubJoinPicker = false
    @State private var showSheet = false
    @State private var organizerProfile: AppUser?

    private var uid: String? { session.user?.id }
    private var isOrganizer: Bool { match.isOrganizer(uid) }
    private var isParticipant: Bool { match.isParticipant(uid) }
    private var isFull: Bool { match.participants.count >= match.maxPlayers }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: match.date)
    }

    private var squareColors: [Color] {
        match.type == .five
            ? [Color(hex: "F87171"), Color(hex: "DC2626")]   // Five = rouge
            : [Color(hex: "34D399"), Color(hex: "059669")]   // Foot = vert
    }

    private var isFinalized: Bool { match.status == .played || match.status == .contested }
    @State private var showDismissConfirm = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cardContent
            if isFinalized {
                Button {
                    showDismissConfirm = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.red))
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                }
                .padding(.leading, 22)
                .padding(.bottom, 8)
            }
        }
        .confirmationDialog(
            "Retirer ce match de ta liste ?",
            isPresented: $showDismissConfirm,
            titleVisibility: .visible
        ) {
            Button("Retirer", role: .destructive) {
                guard let matchId = match.id, let uid = session.user?.id else { return }
                Task { try? await FirebaseService.shared.dismissMatch(uid: uid, matchId: matchId) }
            }
        } message: {
            Text("Tu ne le verras plus dans ta liste de matchs. Cette action est irréversible.")
        }
    }

    private var cardContent: some View {
        HStack(spacing: 0) {
            // Barre d'accent colorée — donne du caractère à la carte,
            // reprend la couleur du type de match (rouge Five / vert Foot)
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: squareColors, startPoint: .top, endPoint: .bottom))
                .frame(width: 4)
                .padding(.vertical, 16)

            cardMainContent
                .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(.white)
                .shadow(color: .black.opacity(0.06), radius: 10, y: 5)
        )
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog(
            "Rejoindre ce match ?",
            isPresented: $showJoinConfirm,
            titleVisibility: .visible
        ) {
            Button(session.user?.hasPremium == true ? "Rejoindre" : "Rejoindre • 1 coin") {
                Task { await viewModel.join(match, uid: session.user?.id) }
            }
        } message: {
            Text(session.user?.hasPremium == true
                 ? "Inclus dans ton abonnement Premium."
                 : "1 coin sera déduit, non remboursé si tu quittes.")
        }
        .sheet(isPresented: $showSheet, onDismiss: {
            // Rejoindre/quitter/annuler DEPUIS la feuille elle-même
            // n'avertissait jamais cette liste — elle restait figée
            // jusqu'au prochain cycle des 20s (ou un changement d'onglet
            // qui relance startAutoRefresh). Ici, peu importe ce qui s'est
            // passé dans la feuille, la liste se remet à jour dès qu'on
            // revient dessus.
            Task { await viewModel.refreshNow() }
        }) {
            if let matchId = match.id {
                MatchSheetView(matchId: matchId)
            }
        }
        .sheet(isPresented: $showClubJoinPicker) {
            ClubJoinPickerSheet(match: match, onJoined: {
                Task { await viewModel.refreshNow() }
            })
        }
    }

    private var cardMainContent: some View {
        HStack(alignment: .top, spacing: 14) {
            // Carré de l'heure — tapable pour un aperçu, même effet
            // que le bouton terrain à côté du bouton Rejoindre.
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(colors: squareColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 84, height: 84)
                .overlay(
                    Text(timeText)
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                )
                .shadow(color: squareColors[1].opacity(0.35), radius: 8, y: 4)
                .onTapGesture { showSheet = true }

            // Infos
            VStack(alignment: .leading, spacing: 10) {
                cardTitleRow
                cardLocationRow

                // Score final visible si le match est clôturé
                if (match.status == .played || match.status == .contested),
                   let a = match.scoreA, let b = match.scoreB {
                    Text("\(a) – \(b)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(match.status == .played ? .green : .orange)
                }

                // Barre de progression joueurs — remplace "X/Y joueurs" en texte brut
                playersProgress

                actionButton
                    .padding(.top, 2)
            }
        }
    }

    private var cardTitleRow: some View {
        HStack(spacing: 6) {
            // Pastille de type (5v5 / 11v11) — remplace le "Match FIVE" littéral
            HStack(spacing: 4) {
                Circle()
                    .fill(squareColors[1])
                    .frame(width: 6, height: 6)
                Text(match.type == .five ? "5v5" : "11v11")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Pitcha.navy)
            }

            statusPill

            if match.isRankedMatch {
                rankedBadge
            }

            Spacer()

            // Organisateur : avatar-initiale, discret, sans "Par ..."
            organizerAvatar
        }
    }

    private var rankedBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 8, weight: .bold))
            Text("CLASSÉ")
                .font(.system(size: 9, weight: .heavy))
                .kerning(0.3)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(
                LinearGradient(colors: [Color(hex: "F2C740"), Color(hex: "B8860B")],
                               startPoint: .leading, endPoint: .trailing)
            )
        )
    }

    // Localisation : bien visible, en gras, couleur d'accent —
    // c'est l'info la plus utile de la carte, elle doit sauter aux yeux
    private var cardLocationRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(squareColors[1])
            Text(locationLine)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Pitcha.navy)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if match.status == .pendingValidation {
            Circle().fill(Color.orange).frame(width: 6, height: 6)
        } else if match.status == .played {
            Circle().fill(Color.green).frame(width: 6, height: 6)
        } else if match.status == .contested {
            Circle().fill(Color.red.opacity(0.85)).frame(width: 6, height: 6)
        }
    }

    /// Avatar circulaire avec l'initiale de l'organisateur — remplace "Par {pseudo}".
    /// Tapable : ouvre le profil de l'organisateur (demande d'ami possible
    /// depuis là, comme partout ailleurs où un profil s'affiche).
    private var organizerAvatar: some View {
        let initial = match.organizerPseudo.trimmingCharacters(in: .whitespaces).first.map(String.init)?.uppercased() ?? "?"
        return Button {
            Task {
                if let user = try? await FirebaseService.shared.fetchUsers(uids: [match.organizerId]).first {
                    organizerProfile = user
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Pitcha.navy.opacity(0.10))
                    .frame(width: 22, height: 22)
                Text(initial)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Pitcha.navy)
            }
        }
        .sheet(item: $organizerProfile) { user in
            MiniProfileSheet(user: user, match: match, context: "match", contextId: match.id)
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
        }
    }

    /// Barre de progression fine indiquant le remplissage du match — remplace "X/Y joueurs".
    private var playersProgress: some View {
        let filled = min(match.participants.count, match.maxPlayers)
        let total = max(match.maxPlayers, 1)
        let ratio = CGFloat(filled) / CGFloat(total)

        return HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.12))
                    Capsule()
                        .fill(
                            LinearGradient(colors: squareColors, startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 5)

            Text("\(filled)/\(match.maxPlayers)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private var locationLine: String {
        if let zone = match.zone, !zone.isEmpty, zone != match.location {
            return "\(zone) • \(match.location)"
        }
        return match.location
    }

    // Bouton dynamique selon le rôle ET le statut
    @ViewBuilder
    private var actionButton: some View {
        if match.status == .played || match.status == .contested {
            // Match clôturé : toujours consultable, plus d'action de gestion
            pillButton(
                match.status == .played ? "Voir le résultat" : "Voir le résultat (contesté)",
                colors: match.status == .played
                    ? [Color.green, Color(hex: "15803D")]
                    : [Color.orange, Color(hex: "C2410C")]
            ) {
                showSheet = true
            }
        } else if match.status == .pendingValidation {
            pillButton("⏳ Voter pour le score", colors: [.orange, Color(hex: "EA580C")]) {
                showSheet = true
            }
        } else if isOrganizer {
            pillButton("Gérer le match", colors: [Pitcha.navy, Color(hex: "1E3A5F")]) {
                showSheet = true
            }
        } else if isParticipant {
            pillButton("Voir la feuille de match", colors: [Pitcha.tealDark, Pitcha.teal]) {
                showSheet = true
            }
        } else if isFull {
            Text("Complet")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Capsule().fill(Color.gray.opacity(0.15)))
        } else {
            notJoinedActions
        }
    }

    private var notJoinedActions: some View {
        HStack(spacing: 8) {
            // Bouton aperçu — voir qui est déjà dans le match, sans
            // avoir à s'engager à le rejoindre. Manquait complètement
            // avant : la seule action disponible ici était "Rejoindre".
            Button {
                showSheet = true
            } label: {
                Image(systemName: "sportscourt.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Pitcha.navy)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.06)))
            }

            if match.isRankedMatch {
                pillButton("Rejoindre avec mon club", colors: [Color(hex: "F2C740"), Color(hex: "B8860B")]) {
                    showClubJoinPicker = true
                }
            } else {
                pillButton(session.user?.hasPremium == true ? "Rejoindre" : "Rejoindre • 1 coin", colors: [Pitcha.teal, Pitcha.mint]) {
                    showJoinConfirm = true
                }
            }
        }
    }

    private func pillButton(_ label: String, colors: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                )
        }
    }
}

// MARK: - Choisir son club pour rejoindre un match Classé

struct ClubJoinPickerSheet: View {
    let match: Match
    var onJoined: () -> Void = {}
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var clubs: [Club] = []
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var errorMessage: String?

    /// Seuls les clubs dont je suis capitaine ET dont aucun titulaire n'est
    /// déjà dans ce match peuvent rejoindre.
    private var eligibleClubs: [Club] {
        guard let uid = session.user?.id else { return [] }
        return clubs.filter { club in
            club.captainId == uid &&
            club.isReadyForRanked &&
            club.starterIds.allSatisfy { !match.participants.contains($0) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if eligibleClubs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "shield.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Aucun club disponible")
                            .font(.headline)
                            .foregroundStyle(Pitcha.navy)
                        Text("Il te faut être capitaine d'un club avec 5 titulaires complets, et aucun de ses joueurs ne doit déjà être dans ce match.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(eligibleClubs) { club in
                        Button {
                            join(club: club)
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(CrestPalette.color(named: club.crestColorName).gradient)
                                        .frame(width: 42, height: 42)
                                    Image(systemName: club.crestIcon ?? "shield.fill")
                                        .foregroundStyle(.white)
                                }
                                Text(club.name).font(.subheadline.weight(.bold))
                                Spacer()
                                if isJoining {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(isJoining)
                    }
                    .listStyle(.plain)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .navigationTitle("Choisis ton club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } }
            }
            .task {
                guard let uids = session.user?.clubIdsValue, !uids.isEmpty else { isLoading = false; return }
                clubs = (try? await FirebaseService.shared.fetchMyClubs(clubIds: uids)) ?? []
                isLoading = false
            }
        }
    }

    private func join(club: Club) {
        guard let matchId = match.id, let captainUid = session.user?.id else { return }
        isJoining = true
        errorMessage = nil
        Task {
            do {
                try await FirebaseService.shared.joinRankedMatchWithClub(matchId: matchId, club: club, captainUid: captainUid)
                onJoined()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isJoining = false
        }
    }
}

// MARK: - Bandeau discret "tes prochains matchs organisés"

struct MyUpcomingMatchesBanner: View {
    let matches: [Match]
    let onTap: (Match) -> Void

    var body: some View {
        if !matches.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(matches) { match in
                        Button { onTap(match) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.caption2)
                                Text(match.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                                    .font(.caption.weight(.bold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Pitcha.teal.opacity(0.12)))
                            .foregroundStyle(Pitcha.tealDark)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 4)
            .transition(.opacity)
        }
    }
}
