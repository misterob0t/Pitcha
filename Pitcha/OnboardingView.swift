import SwiftUI

// MARK: - Onboarding premier lancement — affiché une seule fois, avant l'écran
// de connexion, pour donner un aperçu de l'app avant de demander un compte.

struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let colors: [Color]
}

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "sportscourt.fill",
            title: "Organise tes matchs",
            subtitle: "Crée ou rejoins un match public ou privé, Five ou 11 contre 11, près de chez toi.",
            colors: [Pitcha.teal, Pitcha.tealDark]
        ),
        OnboardingPage(
            icon: "chart.line.uptrend.xyaxis",
            title: "Fais progresser ta carte",
            subtitle: "Chaque match Classé te fait gagner des PL. Grimpe les divisions, de District à Ligue 1.",
            colors: [Color(hex: "F2C740"), Color(hex: "B8860B")]
        ),
        OnboardingPage(
            icon: "trophy.fill",
            title: "Grimpe le classement",
            subtitle: "Compare-toi aux joueurs de ta ville et deviens la référence locale.",
            colors: [Pitcha.navy, Color(hex: "1E3A5F")]
        )
    ]

    var body: some View {
        ZStack {
            PitchaBackground()

            VStack(spacing: 0) {
                // Bouton "Passer" — toujours accessible sauf sur le dernier écran
                HStack {
                    Spacer()
                    if page < pages.count - 1 {
                        Button("Passer") {
                            withAnimation(.snappy) { onComplete() }
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 24)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, p in
                        OnboardingPageView(page: p).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Indicateurs de page, stylisés maison
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Pitcha.teal : Color.gray.opacity(0.25))
                            .frame(width: i == page ? 22 : 8, height: 8)
                    }
                }
                .animation(.snappy, value: page)
                .padding(.bottom, 24)

                Button {
                    if page < pages.count - 1 {
                        withAnimation(.snappy) { page += 1 }
                    } else {
                        onComplete()
                    }
                } label: {
                    Text(page < pages.count - 1 ? "Suivant" : "Commencer")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Pitcha.gradient))
                        .foregroundStyle(.white)
                        .shadow(color: Pitcha.teal.opacity(0.35), radius: 10, y: 5)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
    }
}

// MARK: - Une page de l'onboarding

private struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: page.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 140, height: 140)
                    .shadow(color: page.colors.first?.opacity(0.4) ?? .clear, radius: 20, y: 10)

                Image(systemName: page.icon)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(Pitcha.navy)
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)

            Spacer()
            Spacer()
        }
        .onAppear {
            appeared = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.1)) {
                appeared = true
            }
        }
    }
}
