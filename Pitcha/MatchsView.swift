import SwiftUI

struct MatchsView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var viewModel = MatchsViewModel()
    @State private var showCreateSheet = false

    var body: some View {
        VStack(spacing: 16) {
                // Header : Publics/Privés + ville
                HStack {
                    HStack(spacing: 8) {
                        ForEach(MatchVisibility.allCases, id: \.self) { visibility in
                            PillButton(
                                label: visibility.rawValue,
                                isSelected: viewModel.visibility == visibility
                            ) {
                                viewModel.visibility = visibility
                            }
                        }
                    }

                    Spacer()

                    Menu {
                        ForEach(MatchsViewModel.cities, id: \.self) { city in
                            Button(city) {
                                withAnimation(.snappy) { viewModel.city = city }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.city)
                                .font(.subheadline.bold())
                            Image(systemName: "chevron.down")
                                .font(.caption.bold())
                        }
                        .foregroundStyle(Pitcha.navy)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.06)))
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Strip de jours horizontal
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

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Liste ou état vide
                if viewModel.filteredMatches.isEmpty {
                    Spacer()
                    EmptyMatchesView()
                    Spacer()
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.filteredMatches) { match in
                                MatchCard(match: match, viewModel: viewModel)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 90)
                    }
                }
            }

        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PitchaBackground())
        .overlay(alignment: .bottom) {
            // Coins + FAB en overlay sur la zone safe : au-dessus de la tab bar
            HStack {
                CoinsPill(coins: session.user?.coins ?? 0)
                Spacer()
                PitchaFAB { showCreateSheet = true }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateMatchView(viewModel: viewModel)
        }
    }
}

// MARK: - Chip de jour

struct DayChip: View {
    let date: Date
    let isSelected: Bool
    let action: () -> Void

    private var weekdayText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased() + "."
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
                    .shadow(color: .black.opacity(isSelected ? 0.15 : 0.05), radius: 8, y: 4)
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

// MARK: - Carte de match (carré heure à gauche : vert = Foot, rouge = Five)

struct MatchCard: View {
    let match: Match
    @EnvironmentObject var session: SessionViewModel
    @ObservedObject var viewModel: MatchsViewModel

    @State private var showJoinConfirm = false
    @State private var showSheet = false

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

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Carré de l'heure
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

            // Infos
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Match \(match.type.displayName.uppercased())")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Pitcha.navy)
                    Spacer()
                    Text(match.type == .five ? "5v5" : "11v11")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: "64748B"))
                        )
                }

                HStack(spacing: 4) {
                    Image(systemName: "location.north.fill")
                        .font(.caption2)
                    Text(locationLine)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.caption2)
                        Text("\(match.participants.count)/\(match.maxPlayers) joueurs")
                    }
                    Spacer()
                    Text("Par \(match.organizerPseudo)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                actionButton
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(.white)
                .shadow(color: .black.opacity(0.06), radius: 10, y: 5)
        )
        .confirmationDialog(
            "Rejoindre ce match ?",
            isPresented: $showJoinConfirm,
            titleVisibility: .visible
        ) {
            Button("Rejoindre • 1 coin") {
                Task { await viewModel.join(match, uid: session.user?.id) }
            }
        } message: {
            Text("1 coin sera déduit, non remboursé si tu quittes.")
        }
        .sheet(isPresented: $showSheet) {
            if let matchId = match.id {
                MatchSheetView(matchId: matchId)
            }
        }
    }

    private var locationLine: String {
        if let zone = match.zone, !zone.isEmpty, zone != match.location {
            return "\(zone) • \(match.location)"
        }
        return match.location
    }

    // Bouton dynamique selon le rôle
    @ViewBuilder
    private var actionButton: some View {
        if isOrganizer {
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
            pillButton("Rejoindre • 1 coin", colors: [Pitcha.teal, Pitcha.mint]) {
                showJoinConfirm = true
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
