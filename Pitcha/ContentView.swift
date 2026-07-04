import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        switch session.state {
        case .loading:
            ZStack {
                PitchaBackground()
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(Pitcha.teal)
            }
        case .loggedOut:
            AuthView()
        case .emailNotVerified:
            EmailVerificationView()
        case .loggedIn:
            MainTabView()
        }
    }
}

// MARK: - Observation du clavier

final class KeyboardObserver: ObservableObject {
    @Published var isVisible = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.isVisible = true }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.isVisible = false }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Visibilité de la tab bar (les écrans de chat la masquent)

final class TabBarVisibility: ObservableObject {
    @Published var isHidden = false
}

// MARK: - Séquence unique de navigation par swipe. Chaque swipe avance ou
// recule d'UN SEUL cran dans cette liste — jamais de saut direct entre deux
// onglets principaux si des sous-onglets existent entre les deux.

enum SwipeStop: Int, CaseIterable {
    case boutiquePremium
    case boutiqueCoins
    case equipeTeam
    case equipeFriends
    case matchs
    case profil
    case classementRegional
    case classementNational
    case classementMondial
}

// MARK: - Routeur d'onglets (permet à n'importe quelle vue de changer d'onglet,
// ex : taper sur le solde de coins depuis Matchs pour aller direct sur
// Boutique > Coins, sans passer par la tab bar. Pilote aussi la navigation
// par swipe entre écrans ET sous-onglets.)

final class TabRouter: ObservableObject {
    @Published var selectedTab: Int = 2

    /// Sous-onglet actif dans Boutique : Premium ou Coins
    @Published var boutiqueCategory: ShopCategory = .premium

    /// Sous-onglet actif dans Équipes : 0 = Équipes, 1 = Amis
    @Published var equipesSubTab: Int = 0

    /// Sous-onglet actif dans Classement (Régional/National/Mondial)
    @Published var classementScope: RankScope = .regional

    /// Bascule sur la Boutique directement sur l'onglet Coins.
    func goToCoins() {
        boutiqueCategory = .coins
        selectedTab = 0
    }

    // MARK: - Navigation par swipe

    private var currentStop: SwipeStop {
        switch selectedTab {
        case 0: return boutiqueCategory == .premium ? .boutiquePremium : .boutiqueCoins
        case 1: return equipesSubTab == 0 ? .equipeTeam : .equipeFriends
        case 2: return .matchs
        case 3: return .profil
        case 4:
            switch classementScope {
            case .regional: return .classementRegional
            case .national: return .classementNational
            case .mondial:  return .classementMondial
            }
        default: return .matchs
        }
    }

    private func apply(_ stop: SwipeStop) {
        switch stop {
        case .boutiquePremium:
            selectedTab = 0; boutiqueCategory = .premium
        case .boutiqueCoins:
            selectedTab = 0; boutiqueCategory = .coins
        case .equipeTeam:
            selectedTab = 1; equipesSubTab = 0
        case .equipeFriends:
            selectedTab = 1; equipesSubTab = 1
        case .matchs:
            selectedTab = 2
        case .profil:
            selectedTab = 3
        case .classementRegional:
            selectedTab = 4; classementScope = .regional
        case .classementNational:
            selectedTab = 4; classementScope = .national
        case .classementMondial:
            selectedTab = 4; classementScope = .mondial
        }
    }

    /// Avance d'un cran dans la séquence (swipe vers la gauche).
    func swipeNext() {
        guard let next = SwipeStop(rawValue: currentStop.rawValue + 1) else { return }
        apply(next)
    }

    /// Recule d'un cran dans la séquence (swipe vers la droite).
    func swipePrevious() {
        guard let previous = SwipeStop(rawValue: currentStop.rawValue - 1) else { return }
        apply(previous)
    }
}

// MARK: - Conteneur principal

struct MainTabView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var router = TabRouter()
    @StateObject private var keyboard = KeyboardObserver()
    @StateObject private var tabBarVisibility = TabBarVisibility()

    var body: some View {
        ZStack {
            // Les 5 onglets restent vivants en permanence (pas de switch qui
            // détruit/recrée la vue) : le changement d'onglet devient
            // instantané, plus de rechargement réseau (avatar, stats...) ni
            // de replay des animations d'entrée à chaque tap.
            BoutiqueView()
                .opacity(router.selectedTab == 0 ? 1 : 0)
                .allowsHitTesting(router.selectedTab == 0)

            EquipesView()
                .opacity(router.selectedTab == 1 ? 1 : 0)
                .allowsHitTesting(router.selectedTab == 1)

            MatchsView()
                .opacity(router.selectedTab == 2 ? 1 : 0)
                .allowsHitTesting(router.selectedTab == 2)

            ProfilView()
                .opacity(router.selectedTab == 3 ? 1 : 0)
                .allowsHitTesting(router.selectedTab == 3)

            ClassementView()
                .opacity(router.selectedTab == 4 ? 1 : 0)
                .allowsHitTesting(router.selectedTab == 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(tabBarVisibility)
        .environmentObject(router)
        // Swipe horizontal : avance/recule d'un cran dans la séquence
        // Boutique -> Équipe(Équipe) -> Équipe(Amis) -> Matchs -> Profil ->
        // Classement(Régional/National/Mondial). minimumDistance élevé et
        // ratio horizontal/vertical pour ne pas voler les scrolls internes
        // (bandeau de dates, carrousel de matchs, listes verticales...).
        .gesture(
            DragGesture(minimumDistance: 60, coordinateSpace: .local)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > abs(vertical) * 1.5, abs(horizontal) > 60 else { return }
                    withAnimation(.snappy) {
                        if horizontal < 0 {
                            router.swipeNext()
                        } else {
                            router.swipePrevious()
                        }
                    }
                }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboard.isVisible && !tabBarVisibility.isHidden {
                PitchaTabBar(selected: $router.selectedTab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: keyboard.isVisible)
        .animation(.snappy(duration: 0.25), value: tabBarVisibility.isHidden)
        .sheet(isPresented: $session.showWelcomeBonus) {
            WelcomeBonusView()
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Message de bienvenue (20 coins offerts à l'inscription)

struct WelcomeBonusView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.yellow, .orange],
                            center: .center,
                            startRadius: 4,
                            endRadius: 55
                        )
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: .orange.opacity(0.4), radius: 16, y: 6)

                Image(systemName: "circle.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 6) {
                Text("Bienvenue sur Pitcha ! ⚽")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Pitcha.navy)

                Text("Voilà 20 coins pour commencer l'aventure, mon pote. De quoi rejoindre tes premiers matchs !")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 6) {
                Image(systemName: "circle.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("+20 coins offerts")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Pitcha.navy)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.orange.opacity(0.12)))

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("C'est parti !")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(
                                colors: [Pitcha.tealDark, Pitcha.mint],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                    )
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .padding(.top, 12)
    }
}

// MARK: - Tab bar collée au bas de l'écran

struct PitchaTabBar: View {
    @Binding var selected: Int

    var body: some View {
        HStack {
            tabButton(index: 0, icon: "cart")
            Spacer()
            tabButton(index: 1, icon: "person.3.fill")
            Spacer()
            CenterTabButton(isSelected: selected == 2) { selected = 2 }
            Spacer()
            tabButton(index: 3, icon: "person.fill")
            Spacer()
            tabButton(index: 4, icon: "trophy.fill")
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .fill(.white)
                .shadow(color: .black.opacity(0.10), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(index: Int, icon: String) -> some View {
        Button {
            withAnimation(.snappy) { selected = index }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(selected == index ? Pitcha.teal : Color.gray.opacity(0.55))
                .frame(width: 44, height: 40)
        }
    }
}

// MARK: - Bouton central (ballon qui tourne, design fourni)

struct CenterTabButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                action()
            }
        }) {
            ZStack {
                Circle()
                    .fill(Pitcha.tealDark.opacity(0.15))
                    .frame(width: 48, height: 48)
                    .blur(radius: 8)

                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: isSelected
                                ? [Pitcha.tealDark, Pitcha.mint]
                                : [Color(hex: "1C1C2E"), Color(hex: "16213E")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                    .shadow(
                        color: Pitcha.tealDark.opacity(isSelected ? 0.45 : 0.25),
                        radius: 8, y: 3
                    )

                Image(systemName: "soccerball")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(isSelected ? 15 : 0))
                    .animation(.spring(response: 0.4, dampingFraction: 0.5), value: isSelected)
            }
        }
        .offset(y: -10)
    }
}
