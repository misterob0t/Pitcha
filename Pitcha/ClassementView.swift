import SwiftUI

struct ClassementView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var viewModel = ClassementViewModel()

    var body: some View {
        ZStack {
            PitchaBackground()

            
            ScrollView {
                VStack(spacing: 22) {
                    // Sélecteur de scope en pill blanche
                    ScopeSelector(scope: $viewModel.scope)
                        .padding(.horizontal, 40)
                        .padding(.top, 8)

                    if viewModel.isLoading {
                        ProgressView()
                            .padding(.top, 60)
                    } else if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding()
                    } else if viewModel.players.isEmpty {
                        Text("Aucun joueur classé pour l'instant.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 60)
                    } else {
                        // Classement
                        VStack(spacing: 12) {
                            ForEach(Array(viewModel.players.enumerated()), id: \.element.id) { index, player in
                                RankRow(
                                    rank: index + 1,
                                    player: player,
                                    isMe: viewModel.isMe(player, user: session.user)
                                )
                            }

                            // Ma position si hors du top affiché
                            if viewModel.isOutsideTop(user: session.user),
                               let user = session.user,
                               let rank = viewModel.myRank {
                                RankRow(rank: rank, player: user, isMe: true)
                            }
                        }
                        .padding(.horizontal)

                        // Badges
                        if let user = session.user {
                            BadgesSection(user: user)
                                .padding(.horizontal)
                                .padding(.bottom, 90)
                        }
                    }
                }
            }
            .refreshable {
                await viewModel.load(user: session.user)
            }
        }
        .task {
            await viewModel.load(user: session.user)
        }
    }
}

// MARK: - Sélecteur Régional / National / Mondial

struct ScopeSelector: View {
    @Binding var scope: RankScope

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RankScope.allCases) { item in
                Button {
                    withAnimation(.snappy) { scope = item }
                } label: {
                    Text(item.rawValue)
                        .font(.subheadline.bold())
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule().fill(
                                scope == item
                                    ? AnyShapeStyle(Pitcha.gradient)
                                    : AnyShapeStyle(Color.clear)
                            )
                        )
                        .foregroundStyle(scope == item ? .white : .secondary)
                }
            }
        }
        .padding(5)
        .background(
            Capsule()
                .fill(.white)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        )
    }
}

// MARK: - Ligne de classement

struct RankRow: View {
    let rank: Int
    let player: AppUser
    let isMe: Bool

    private var rankColor: Color {
        switch rank {
        case 1: return Color(red: 0.98, green: 0.82, blue: 0.25)
        case 2: return Color(white: 0.72)
        case 3: return Color(red: 0.8, green: 0.52, blue: 0.25)
        default: return Color.black.opacity(0.07)
        }
    }

    private var statsText: String {
        let perMatch = String(format: "%.1f", player.goalsPerMatch)
        return "\(player.totalMatches) match\(player.totalMatches > 1 ? "s" : "") • \(perMatch) buts/match"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Pastille rang
            ZStack {
                Circle()
                    .fill(rankColor)
                    .frame(width: 34, height: 34)
                Text("\(rank)")
                    .font(.subheadline.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(rank <= 3 ? .white : Pitcha.navy)
            }

            InitialsAvatar(text: player.pseudo, size: 46, cornerStyle: .circle)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(player.pseudo)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Pitcha.navy)
                    if isMe {
                        Text("Vous")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Pitcha.tealDark))
                            .foregroundStyle(.white)
                    }
                }
                Text(statsText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                Text("\(player.totalGoals)")
                    .font(.title2.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(Pitcha.tealDark)
                Text("buts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(isMe ? Pitcha.teal.opacity(0.6) : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Section badges

struct BadgesSection: View {
    let user: AppUser
    @State private var selectedBadge: PlayerBadge?
    @State private var showAllBadges = false

    private var badges: [PlayerBadge] {
        BadgeCatalog.badges(for: user)
    }

    private var unlockedCount: Int {
        badges.filter(\.isUnlocked).count
    }

    var body: some View {
        VStack(spacing: 14) {
            // Titre
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.gray.opacity(0.25))
                    .frame(height: 1)
                Image(systemName: "medal.fill")
                    .foregroundStyle(.yellow)
                Text("MES BADGES")
                    .font(.subheadline.weight(.heavy))
                    .kerning(2.5)
                    .foregroundStyle(Pitcha.navy)
                    .fixedSize()
                Rectangle()
                    .fill(Color.gray.opacity(0.25))
                    .frame(height: 1)
            }

            // Carte badges
            VStack(spacing: 16) {
                HStack {
                    Text("\(unlockedCount)/\(badges.count) débloqués")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Pitcha.navy)
                    Spacer()
                    Button {
                        showAllBadges = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("Voir tout")
                                .font(.subheadline.bold())
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                        }
                        .foregroundStyle(Pitcha.tealDark)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(badges) { badge in
                            Button {
                                selectedBadge = badge
                            } label: {
                                BadgeItem(badge: badge)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
            )
        }
        .sheet(item: $selectedBadge) { badge in
            BadgeDetailSheet(badge: badge)
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAllBadges) {
            AllBadgesSheet(user: user)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Tous les badges (Voir tout)

struct AllBadgesSheet: View {
    let user: AppUser

    private var badges: [PlayerBadge] {
        BadgeCatalog.badges(for: user)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(badges) { badge in
                        HStack(spacing: 14) {
                            ZStack {
                                Image(systemName: badge.shape)
                                    .font(.system(size: 52))
                                    .foregroundStyle(
                                        badge.isUnlocked
                                            ? AnyShapeStyle(Pitcha.gradient)
                                            : AnyShapeStyle(Color(red: 0.25, green: 0.28, blue: 0.35))
                                    )
                                Image(systemName: badge.icon)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(badge.isUnlocked ? .white : Color.gray.opacity(0.7))
                            }
                            .frame(width: 60)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(badge.name)
                                        .font(.subheadline.weight(.heavy))
                                        .foregroundStyle(Pitcha.navy)
                                    Spacer()
                                    Text(badge.isUnlocked ? "Débloqué ✓" : "\(badge.clampedProgress)/\(badge.target)")
                                        .font(.caption.weight(.heavy))
                                        .monospacedDigit()
                                        .foregroundStyle(badge.isUnlocked ? Pitcha.teal : .secondary)
                                }
                                Text(badge.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.gray.opacity(0.2))
                                        Capsule()
                                            .fill(Pitcha.gradient)
                                            .frame(width: geo.size.width * CGFloat(badge.clampedProgress) / CGFloat(badge.target))
                                    }
                                }
                                .frame(height: 6)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.white)
                                .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
                        )
                    }
                }
                .padding()
            }
            .background(Pitcha.background)
            .navigationTitle("Mes badges")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Détail d'un badge (tap)

struct BadgeDetailSheet: View {
    let badge: PlayerBadge

    var body: some View {
        VStack(spacing: 18) {
            // Le badge en grand
            ZStack {
                Image(systemName: badge.shape)
                    .font(.system(size: 120))
                    .foregroundStyle(
                        badge.isUnlocked
                            ? AnyShapeStyle(Pitcha.gradient)
                            : AnyShapeStyle(Color(red: 0.25, green: 0.28, blue: 0.35))
                    )
                Image(systemName: badge.icon)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(badge.isUnlocked ? .white : Color.gray.opacity(0.7))
            }
            .padding(.top, 28)

            Text(badge.name)
                .font(.title2.weight(.heavy))
                .foregroundStyle(Pitcha.navy)

            // Descriptif (ex : "Marquer 3 buts en 1 match")
            Text(badge.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Barre de progression
            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.2))
                        Capsule()
                            .fill(Pitcha.gradient)
                            .frame(width: geo.size.width * CGFloat(badge.clampedProgress) / CGFloat(badge.target))
                    }
                }
                .frame(height: 12)

                Text(badge.isUnlocked ? "Débloqué ✓" : "\(badge.clampedProgress)/\(badge.target)")
                    .font(.subheadline.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(badge.isUnlocked ? Pitcha.teal : .secondary)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }
}

struct BadgeItem: View {
    let badge: PlayerBadge

    private var mainColor: Color {
        badge.isUnlocked ? Pitcha.teal : Color(red: 0.25, green: 0.28, blue: 0.35)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Image(systemName: badge.shape)
                    .font(.system(size: 64))
                    .foregroundStyle(
                        badge.isUnlocked
                            ? AnyShapeStyle(Pitcha.gradient)
                            : AnyShapeStyle(mainColor)
                    )
                Image(systemName: badge.icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(badge.isUnlocked ? .white : Color.gray.opacity(0.7))
            }
            .frame(height: 70)

            // Mini barre de progression
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.2))
                    Capsule()
                        .fill(Pitcha.teal)
                        .frame(width: geo.size.width * CGFloat(badge.clampedProgress) / CGFloat(badge.target))
                }
            }
            .frame(width: 44, height: 4)

            Text(badge.name)
                .font(.caption.bold())
                .foregroundStyle(badge.isUnlocked ? Pitcha.navy : .secondary)
                .lineLimit(1)

            Text(badge.isUnlocked ? "Débloqué ✓" : "\(badge.clampedProgress)/\(badge.target)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(badge.isUnlocked ? Pitcha.teal : .secondary)
        }
        .frame(width: 84)
    }
}
