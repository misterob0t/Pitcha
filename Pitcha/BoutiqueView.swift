import SwiftUI

// MARK: - Vue principale

struct BoutiqueView: View {
    @EnvironmentObject var session: SessionViewModel
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var router: TabRouter
    @StateObject private var viewModel = BoutiqueViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tabs (Premium / Coins)
                CategoryTabs(selected: $viewModel.selectedCategory)
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Feedback messages
                Group {
                    if let success = viewModel.successMessage {
                        Text(success)
                            .font(.footnote.bold())
                            .foregroundStyle(.green)
                    } else if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.top, 6)
                .animation(.snappy, value: viewModel.successMessage)

                // Contenu
                ScrollView {
                    switch viewModel.selectedCategory {
                    case .premium:
                        PremiumPage(viewModel: viewModel)
                    case .coins:
                        CoinsPage(viewModel: viewModel)
                    }
                }
                .task {
                    await viewModel.onAppear()
                    // Navigation demandée depuis un autre onglet (ex: taper
                    // sur le solde de coins) : ouvre directement Coins puis
                    // consomme la demande pour ne pas la rejouer ensuite.
                    if let requested = router.pendingBoutiqueCategory {
                        viewModel.selectedCategory = requested
                        router.pendingBoutiqueCategory = nil
                    }
                }
            }
            .background(
                LinearGradient(
                    colors: [Color.teal.opacity(0.08), Color(.systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if let user = session.user {
                        CoinsBadge(coins: user.coins)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: viewModel.purchaseTrigger)
        }
    }
}

// MARK: - Badge coins toolbar

private struct CoinsBadge: View {
    let coins: Int
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
            Text("\(coins)")
                .fontWeight(.bold)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .animation(.snappy, value: coins)
    }
}

// MARK: - Tabs

struct CategoryTabs: View {
    @Binding var selected: ShopCategory

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ShopCategory.allCases) { category in
                Button {
                    withAnimation(.snappy) { selected = category }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: category.icon)
                            .font(.caption)
                        Text(category.rawValue)
                            .font(.subheadline.weight(.bold))
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        selected == category
                            ? AnyShapeStyle(LinearGradient(colors: [.teal, Color(red: 0.22, green: 0.82, blue: 0.72)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color(.secondarySystemBackground))
                    )
                    .foregroundStyle(selected == category ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}

// MARK: - Page Premium

private struct PremiumPage: View {
    @ObservedObject var viewModel: BoutiqueViewModel
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        VStack(spacing: 20) {
            // Hero card
            PremiumHeroCard(isPremium: session.user?.hasPremium ?? false)
                .padding(.horizontal)
                .padding(.top, 16)

            // Avantages
            PremiumPerksSection()
                .padding(.horizontal)

            // Plans d'abonnement (masqués si déjà premium)
            if !(session.user?.hasPremium ?? false) {
                PremiumPlansSection(viewModel: viewModel)
                    .padding(.horizontal)
            } else {
                PremiumActiveCard(user: session.user)
                    .padding(.horizontal)
            }

            // Bouton restaurer les achats (obligatoire Apple)
            Button {
                Task { await viewModel.restorePurchases(user: session.user) }
            } label: {
                Text("Restaurer les achats")
                    .font(.caption)
                    .foregroundStyle(Pitcha.teal)
                    .underline()
            }
            .padding(.bottom, 8)

            Text("Paiements gérés par Apple. L'abonnement se renouvelle automatiquement sauf résiliation 24h avant la date d'échéance.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
    }
}

// MARK: - Hero card premium

private struct PremiumHeroCard: View {
    let isPremium: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.08, green: 0.38, blue: 0.38),
                                 Color(red: 0.04, green: 0.20, blue: 0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ParticlesView()
                .clipShape(RoundedRectangle(cornerRadius: 26))

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Pitcha.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pitcha Premium")
                            .font(.title2.weight(.black))
                            .foregroundStyle(.white)
                        Text(isPremium ? "Abonnement actif ✓" : "Passe au niveau supérieur")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                }
            }
            .padding(22)
        }
        .frame(height: 110)
        .shadow(color: .teal.opacity(0.35), radius: 14, y: 8)
    }
}

// MARK: - Section avantages

private struct PremiumPerksSection: View {
    private let perks: [(icon: String, color: Color, title: String, detail: String)] = [
        ("bolt.fill",         .yellow,  "Matchs gratuits",    "Rejoins tous les matchs sans dépenser de coins"),
        ("chart.line.uptrend.xyaxis", Pitcha.teal, "XP × 1,5",  "Progresse 50% plus vite après chaque match"),
        ("crown.fill",        Pitcha.gold, "Badge Premium",   "Affiche ton statut sur ta carte joueur"),
        ("circle.circle.fill", .orange, "50 coins offerts",   "Crédités dès l'activation de ton abonnement"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Avantages inclus")
                .font(.headline.weight(.heavy))
                .foregroundStyle(Pitcha.navy)

            VStack(spacing: 8) {
                ForEach(perks, id: \.title) { perk in
                    PerkRow(icon: perk.icon, color: perk.color, title: perk.title, detail: perk.detail)
                }
            }
        }
        .padding(18)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

private struct PerkRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Pitcha.navy)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Pitcha.teal)
                .font(.system(size: 18))
        }
    }
}

// MARK: - Plans d'abonnement

private struct PremiumPlansSection: View {
    @ObservedObject var viewModel: BoutiqueViewModel
    @EnvironmentObject var session: SessionViewModel
    @State private var selectedPlan: PremiumPlan = .monthly

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choisir un plan")
                .font(.headline.weight(.heavy))
                .foregroundStyle(Pitcha.navy)

            // Sélecteur mensuel / annuel
            HStack(spacing: 10) {
                ForEach(PremiumPlan.allCases, id: \.rawValue) { plan in
                    PlanPill(plan: plan, isSelected: selectedPlan == plan) {
                        withAnimation(.snappy) { selectedPlan = plan }
                    }
                }
            }

            // Bouton d'abonnement
            Button {
                Task { await viewModel.subscribe(plan: selectedPlan, user: session.user) }
            } label: {
                Group {
                    if viewModel.isWorking {
                        ProgressView().tint(.white)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(Pitcha.gold)
                            Text("S'abonner · \(selectedPlan.priceLabel)")
                                .fontWeight(.bold)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.08, green: 0.38, blue: 0.38),
                                     Color(red: 0.10, green: 0.62, blue: 0.58)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                )
                .foregroundStyle(.white)
                .shadow(color: .teal.opacity(0.35), radius: 8, y: 4)
            }
            .disabled(viewModel.isWorking)

            // Badge économie annuel
            if selectedPlan == .yearly {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.caption)
                    Text("Économise 44% par rapport au mensuel")
                        .font(.caption.bold())
                }
                .foregroundStyle(Pitcha.teal)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Pitcha.teal.opacity(0.10))
                .clipShape(Capsule())
            }
        }
        .padding(18)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

private struct PlanPill: View {
    let plan: PremiumPlan
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(plan.displayName)
                    .font(.subheadline.weight(.bold))
                Text(plan.priceLabel)
                    .font(.caption)
                    .opacity(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isSelected
                    ? AnyShapeStyle(LinearGradient(
                        colors: [Color(red: 0.08, green: 0.38, blue: 0.38),
                                 Color(red: 0.10, green: 0.62, blue: 0.58)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(Color(.secondarySystemBackground))
            )
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Color.clear : Color(.separator), lineWidth: 1)
            )
        }
    }
}

// MARK: - Carte abonnement actif

private struct PremiumActiveCard: View {
    let user: AppUser?

    private var expiryText: String {
        guard let exp = user?.premiumExpiresAt else { return "Actif" }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.locale = Locale(identifier: "fr_FR")
        return "Expire le \(formatter.string(from: exp))"
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 28))
                .foregroundStyle(Pitcha.gold)

            VStack(alignment: .leading, spacing: 4) {
                Text("Abonnement actif")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Pitcha.navy)
                Text(expiryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(Pitcha.teal)
        }
        .padding(18)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

// MARK: - Page Coins

private struct CoinsPage: View {
    @ObservedObject var viewModel: BoutiqueViewModel
    @EnvironmentObject var session: SessionViewModel

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 16) {
            // Solde actuel
            if let user = session.user {
                CoinsBalanceCard(coins: user.coins)
                    .padding(.horizontal)
                    .padding(.top, 16)
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(ShopCatalog.coinPacks) { pack in
                    CoinPackCard(pack: pack) {
                        Task { await viewModel.buyCoins(pack, user: session.user) }
                    }
                }
            }
            .padding(.horizontal)

            Text("Paiements sécurisés par Apple.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
    }
}

private struct CoinsBalanceCard: View {
    let coins: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                    .frame(width: 50, height: 50)
                Image(systemName: "circle.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Ton solde")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(coins) coins")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Pitcha.navy)
                    .contentTransition(.numericText())
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

struct CoinPackCard: View {
    let pack: CoinPack
    let onBuy: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                    .frame(width: 54, height: 54)
                Image(systemName: "circle.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }

            Text("\(pack.amount)")
                .font(.title3.weight(.heavy))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(pack.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button(action: onBuy) {
                Text(pack.priceLabel)
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(Color.teal)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

// MARK: - Particules scintillantes (réutilisées du hero card)

struct ParticlesView: View {
    private struct Particle {
        let x: CGFloat
        let baseY: CGFloat
        let size: CGFloat
        let speed: Double
        let phase: Double
    }

    private let particles: [Particle] = (0..<14).map { _ in
        Particle(
            x: .random(in: 0...1),
            baseY: .random(in: 0...1),
            size: .random(in: 2...5),
            speed: .random(in: 0.3...0.9),
            phase: .random(in: 0...(2 * .pi))
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for particle in particles {
                    let y = (particle.baseY - CGFloat(t * particle.speed).truncatingRemainder(dividingBy: 1) + 1)
                        .truncatingRemainder(dividingBy: 1)
                    let opacity = 0.25 + 0.55 * abs(sin(t * 2 + particle.phase))
                    let rect = CGRect(
                        x: particle.x * size.width,
                        y: y * size.height,
                        width: particle.size,
                        height: particle.size
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
