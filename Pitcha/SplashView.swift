import SwiftUI

/// Écran de démarrage affiché pendant le chargement de la config distante.
/// Ajoute ton logo PNG sans fond dans Assets.xcassets avec le nom "PitchaLogo".
struct SplashView: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            PitchaBackground()

            Image("PitchaLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(
                        .linear(duration: 2)
                        .repeatForever(autoreverses: false)
                    ) {
                        rotation = 360
                    }
                }
        }
    }
}
