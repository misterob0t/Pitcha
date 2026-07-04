import SwiftUI

// MARK: - Écran de maintenance

struct MaintenanceView: View {
    let message: String

    var body: some View {
        ZStack {
            PitchaBackground()
            VStack(spacing: 24) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Pitcha.gradient)
                Text("Maintenance en cours")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Pitcha.navy)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Text("Merci de votre patience ⚽️")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
        }
    }
}

// MARK: - Mise à jour forcée

struct ForceUpdateView: View {
    var body: some View {
        ZStack {
            PitchaBackground()
            VStack(spacing: 24) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Pitcha.gradient)
                Text("Mise à jour requise")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Pitcha.navy)
                Text("Une nouvelle version de Pitcha est disponible. Mets à jour l'app pour continuer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    if let url = URL(string: "itms-apps://itunes.apple.com/app/idTON_APP_ID") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Mettre à jour")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Pitcha.gradient))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                }
            }
            .padding(32)
        }
    }
}

// MARK: - Mise à jour conseillée (bannière non-bloquante)

struct UpdateBanner: View {
    @Binding var dismissed: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.title3)
                .foregroundStyle(Pitcha.tealDark)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mise à jour disponible")
                    .font(.subheadline.bold())
                    .foregroundStyle(Pitcha.navy)
                Text("Une nouvelle version de Pitcha est prête.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if let url = URL(string: "itms-apps://itunes.apple.com/app/idTON_APP_ID") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Mettre à jour")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Pitcha.gradient))
            }
            Button { dismissed = true } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        )
        .padding(.horizontal)
    }
}

// MARK: - Bannière discrète hors ligne (coin supérieur)

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.caption.bold())
            Text("Hors ligne · certaines données peuvent être obsolètes")
                .font(.caption)
            Spacer()
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.10))
        .overlay(
            Rectangle().frame(height: 0.5)
                .foregroundStyle(Color.orange.opacity(0.25)),
            alignment: .bottom
        )
    }
}

// MARK: - Placeholder inline (remplace uniquement la liste/contenu dynamique)

struct OfflineInlineView: View {
    var message: String = "Reconnecte-toi pour voir les matchs"
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 36))
                .foregroundStyle(Color.gray.opacity(0.4))
            Text(message)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }
}

// MARK: - Input désactivé hors ligne

struct OfflineChatBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash").font(.caption)
            Text("Pas de connexion · les messages ne peuvent pas être envoyés")
                .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.85))
    }
}

// MARK: - Écran support / feedback

struct SupportView: View {
    let email: String
    let message: String
    @State private var feedback = ""
    @State private var sent = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Pitcha.gradient)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ton message")
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(Pitcha.navy)
                        TextEditor(text: $feedback)
                            .frame(minHeight: 120)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.gray.opacity(0.08))
                            )
                    }

                    if sent {
                        Label("Merci ! On te répond dès que possible.", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            // Ouvre Mail avec le feedback pré-rempli
                            let subject = "Feedback Pitcha".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            let body = feedback.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let url = URL(string: "mailto:\(email)?subject=\(subject)&body=\(body)") {
                                UIApplication.shared.open(url)
                                sent = true
                            }
                        } label: {
                            Text("Envoyer")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(RoundedRectangle(cornerRadius: 16)
                                    .fill(feedback.isEmpty ? AnyShapeStyle(Color.gray.opacity(0.2)) : AnyShapeStyle(Pitcha.gradient)))
                                .foregroundStyle(feedback.isEmpty ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.white))
                        }
                        .disabled(feedback.isEmpty)
                    }

                    Divider()

                    HStack(spacing: 6) {
                        Image(systemName: "envelope")
                            .font(.caption)
                        Text(email)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .background(Pitcha.background)
            .navigationTitle("Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}
