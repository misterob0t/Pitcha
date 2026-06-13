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
            .sink { [weak self] _ in self?.isVisible = true }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in self?.isVisible = false }
            .store(in: &cancellables)
    }
}

// MARK: - Visibilité de la tab bar (les écrans de chat la masquent)

final class TabBarVisibility: ObservableObject {
    @Published var isHidden = false
}

// MARK: - Conteneur principal

struct MainTabView: View {
    @State private var selectedTab = 2
    @StateObject private var keyboard = KeyboardObserver()
    @StateObject private var tabBarVisibility = TabBarVisibility()

    var body: some View {
        Group {
            switch selectedTab {
            case 0: BoutiqueView()
            case 1: EquipesView()
            case 2: MatchsView()
            case 3: ProfilView()
            default: ClassementView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(tabBarVisibility)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboard.isVisible && !tabBarVisibility.isHidden {
                PitchaTabBar(selected: $selectedTab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: keyboard.isVisible)
        .animation(.snappy(duration: 0.25), value: tabBarVisibility.isHidden)
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
                    .fill(Color(hex: "0F766E").opacity(0.15))
                    .frame(width: 48, height: 48)
                    .blur(radius: 8)

                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: isSelected
                                ? [Color(hex: "0F766E"), Color(hex: "2DD4BF")]
                                : [Color(hex: "1C1C2E"), Color(hex: "16213E")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                    .shadow(
                        color: Color(hex: "0F766E").opacity(isSelected ? 0.45 : 0.25),
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
