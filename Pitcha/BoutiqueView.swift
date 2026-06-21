import SwiftUI

struct BoutiqueView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var viewModel = BoutiqueViewModel()

    var body: some View {
        NavigationStack {
            boutiqueContent
                .blur(radius: 18)
                .disabled(true)
                .overlay(Pitcha.background.opacity(0.55))
                .overlay(
                    VStack(spacing: 14) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Pitcha.tealDark)
                        Text("Boutique bientôt disponible")
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(Pitcha.navy)
                        Text("Les cosmétiques arrivent dans une\nprochaine mise à jour.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .background(
                        RoundedRectangle(cornerRadius: 26)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                    )
                )
        }
    }

    private var boutiqueContent: some View {
        Group {
            VStack(spacing: 0) {
                // Tabs catégories en haut
                CategoryTabs(selected: $viewModel.selectedCategory)
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Messages
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
                    case .cosmetics:
                        CosmeticsGrid(viewModel: viewModel)
                    case .premium:
                        PremiumList(viewModel: viewModel)
                    case .coins:
                        CoinsGrid(viewModel: viewModel)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let user = session.user {
                        HStack(spacing: 4) {
                            Image(systemName: "circle.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                            Text("\(user.coins)")
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                        .animation(.snappy, value: user.coins)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: viewModel.purchaseTrigger)
        }
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
                            ? AnyShapeStyle(LinearGradient(colors: [.teal, .mint], startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color(.secondarySystemBackground))
                    )
                    .foregroundStyle(selected == category ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}

// MARK: - Cosmétiques

struct CosmeticsGrid: View {
    @ObservedObject var viewModel: BoutiqueViewModel
    @EnvironmentObject var session: SessionViewModel

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(ShopCatalog.cosmetics) { item in
                CosmeticCard(
                    item: item,
                    isOwned: session.user?.owned.contains(item.id) ?? false,
                    canAfford: (session.user?.coins ?? 0) >= item.price
                ) {
                    Task { await viewModel.buyCosmetic(item, user: session.user) }
                }
            }
        }
        .padding()
    }
}

struct CosmeticCard: View {
    let item: CosmeticItem
    let isOwned: Bool
    let canAfford: Bool
    let onBuy: () -> Void

    private var gradient: LinearGradient {
        LinearGradient(
            colors: item.colors.map { colorFromName($0) },
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(gradient)
                    .frame(height: 90)
                Image(systemName: item.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }

            Text(item.name)
                .font(.subheadline.bold())
                .lineLimit(1)

            if isOwned {
                Label("Possédé", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                    .frame(height: 32)
            } else {
                Button(action: onBuy) {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                        Text("\(item.price)")
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(canAfford ? Color.teal : Color.gray.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .disabled(!canAfford)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

// MARK: - Premium (avec particules animées)

struct PremiumList: View {
    @ObservedObject var viewModel: BoutiqueViewModel
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        VStack(spacing: 14) {
            ForEach(ShopCatalog.premiumPacks) { pack in
                PremiumPackCard(
                    pack: pack,
                    canAfford: (session.user?.coins ?? 0) >= pack.price
                ) {
                    Task { await viewModel.buyPack(pack, user: session.user) }
                }
            }
        }
        .padding()
    }
}

struct PremiumPackCard: View {
    let pack: PremiumPack
    let canAfford: Bool
    let onBuy: () -> Void

    var body: some View {
        ZStack {
            // Fond dégradé
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.1, green: 0.55, blue: 0.55),
                            Color(red: 0.05, green: 0.3, blue: 0.4)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Particules scintillantes
            ParticlesView()
                .clipShape(RoundedRectangle(cornerRadius: 22))

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.yellow)
                        Text(pack.name)
                            .font(.headline.bold())
                    }
                    Text(pack.tagline)
                        .font(.caption)
                        .opacity(0.85)
                    Text("+\(pack.skillPoints) points de compétence")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.2))
                        .clipShape(Capsule())
                }

                Spacer()

                Button(action: onBuy) {
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                            Text("\(pack.price)")
                                .font(.subheadline.bold())
                                .monospacedDigit()
                                .minimumScaleFactor(0.7)
                        }
                        Text("Acheter")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(canAfford ? Color.yellow : Color.gray.opacity(0.5))
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canAfford)
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(height: 110)
        .shadow(color: .teal.opacity(0.3), radius: 10, y: 6)
    }
}

/// Particules scintillantes façon Clash Royale (Canvas + TimelineView, léger).
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
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(opacity))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Coins

struct CoinsGrid: View {
    @ObservedObject var viewModel: BoutiqueViewModel
    @EnvironmentObject var session: SessionViewModel

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(ShopCatalog.coinPacks) { pack in
                    CoinPackCard(pack: pack) {
                        Task { await viewModel.buyCoins(pack, user: session.user) }
                    }
                }
            }
            .padding()

            Text("Achats de démonstration — l'intégration App Store (StoreKit) arrivera avant la publication.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
        }
    }
}

struct CoinPackCard: View {
    let pack: CoinPack
    let onBuy: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                    )
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

// MARK: - Helper couleur

private func colorFromName(_ name: String) -> Color {
    switch name {
    case "yellow": return .yellow
    case "orange": return .orange
    case "cyan": return .cyan
    case "purple": return .purple
    case "gray": return .gray
    case "black": return .black
    case "indigo": return .indigo
    case "red": return .red
    case "blue": return .blue
    default: return .teal
    }
}
