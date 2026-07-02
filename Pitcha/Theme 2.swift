import SwiftUI

// MARK: - Design system Pitcha

enum Pitcha {
    static let navy = Color(red: 0.09, green: 0.11, blue: 0.20)
    static let tealDark = Color(red: 0.04, green: 0.42, blue: 0.42)
    static let teal = Color(red: 0.10, green: 0.62, blue: 0.58)
    static let mint = Color(red: 0.22, green: 0.82, blue: 0.72)
    static let background = Color(red: 0.94, green: 0.97, blue: 0.97)
    static let gold = Color(red: 0.95, green: 0.78, blue: 0.25)

    static var gradient: LinearGradient {
        LinearGradient(
            colors: [tealDark, mint],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var goldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1, green: 0.65, blue: 0.15), Color(red: 0.98, green: 0.45, blue: 0.1)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Color depuis hex

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.replacingOccurrences(of: "#", with: ""))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

// MARK: - Fond avec forme diagonale

struct PitchaBackground: View {
    var body: some View {
        ZStack {
            Pitcha.background
            GeometryReader { geo in
                Path { path in
                    path.move(to: CGPoint(x: geo.size.width * 0.55, y: 0))
                    path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.4))
                    path.closeSubpath()
                }
                .fill(Pitcha.mint.opacity(0.10))

                Path { path in
                    path.move(to: CGPoint(x: 0, y: geo.size.height * 0.25))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.12))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.3))
                    path.addLine(to: CGPoint(x: 0, y: geo.size.height * 0.45))
                    path.closeSubpath()
                }
                .fill(.white.opacity(0.5))
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Bouton flottant +

struct PitchaFAB: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(Pitcha.gradient))
                .shadow(color: Pitcha.teal.opacity(0.45), radius: 10, y: 6)
        }
    }
}

// MARK: - Pastille coins

struct CoinsPill: View {
    let coins: Int

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 24, height: 24)
                Text("$")
                    .font(.caption.bold())
                    .foregroundStyle(Color(red: 0.7, green: 0.5, blue: 0))
            }
            Text("\(coins)")
                .font(.headline.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Pitcha.navy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(.white))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        .animation(.snappy, value: coins)
    }
}

// MARK: - Avatar initiales avec dégradé

struct InitialsAvatar: View {
    let text: String
    var size: CGFloat = 52
    var cornerStyle: CornerStyle = .rounded

    enum CornerStyle { case rounded, circle }

    var body: some View {
        ZStack {
            Group {
                if cornerStyle == .circle {
                    Circle().fill(Pitcha.gradient)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.32).fill(Pitcha.gradient)
                }
            }
            .frame(width: size, height: size)

            Text(String(text.prefix(2)).uppercased())
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Pill bouton (Publics/Privés etc.)

struct PillButton: View {
    let label: String
    let isSelected: Bool
    /// Couleur de fond quand sélectionné. Par défaut le dégradé habituel
    /// (vert/teal) ; peut être surchargé au cas par cas (ex: or pour Tournois)
    /// sans affecter les autres usages de PillButton dans l'app.
    var selectedFill: AnyShapeStyle = AnyShapeStyle(Pitcha.gradient)
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Text(label.uppercased())
                .font(.caption.weight(.heavy))
                .kerning(1.2)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(
                    Capsule().fill(
                        isSelected
                            ? selectedFill
                            : AnyShapeStyle(Color.black.opacity(0.06))
                    )
                )
                .foregroundStyle(isSelected ? .white : .secondary)
        }
    }
}

// MARK: - Champ de texte stylé réutilisable

struct PitchaTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Pitcha.tealDark)
                .frame(width: 20)
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .font(.subheadline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.gray.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(text.isEmpty ? Color.clear : Pitcha.teal.opacity(0.4), lineWidth: 1.5)
                )
        )
    }
}
