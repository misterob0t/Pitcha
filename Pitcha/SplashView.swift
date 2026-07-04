import SwiftUI

/// Écran de démarrage affiché pendant le chargement de la config distante.
/// Ajoute ton logo PNG sans fond dans Assets.xcassets avec le nom "PitchaLogo".
struct SplashView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            PitchaBackground()

            Image("PitchaLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .scaleEffect(pulse ? 1.08 : 0.94)
                .opacity(pulse ? 1.0 : 0.75)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 1.1)
                        .repeatForever(autoreverses: true)
                    ) {
                        pulse = true
                    }
                }
        }
    }
}
