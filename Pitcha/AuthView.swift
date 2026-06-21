import SwiftUI

// MARK: - Flux d'authentification par numéro de téléphone

struct AuthView: View {
    @EnvironmentObject var session: SessionViewModel
    @State private var phone = ""
    @State private var code = ""
    @State private var step: Step = .phoneEntry

    enum Step { case phoneEntry, codeEntry }

    var body: some View {
        ZStack {
            PitchaBackground()
            VStack(spacing: 28) {
                // Logo
                VStack(spacing: 4) {
                    Image(systemName: "soccerball.inverse")
                        .font(.system(size: 64, weight: .heavy))
                        .foregroundStyle(Pitcha.gradient)
                    Text("PITCHA")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(Pitcha.navy)
                    Text("Le foot, gamifié.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                VStack(spacing: 18) {
                    switch step {
                    case .phoneEntry: phoneEntryCard
                    case .codeEntry: codeEntryCard
                    }

                    if let error = session.errorMessage {
                        Text(error)
                            .font(.footnote).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: Étape 1 : numéro de téléphone

    private var phoneEntryCard: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ton numéro de téléphone")
                    .font(.headline.weight(.heavy)).foregroundStyle(Pitcha.navy)
                Text("Un SMS de vérification te sera envoyé.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Text("🇫🇷 +33")
                    .font(.subheadline.bold())
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.12)))
                TextField("6 12 34 56 78", text: $phone)
                    .keyboardType(.phonePad)
                    .font(.subheadline)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.08)))
            }

            PitchaButton(
                label: session.isWorking ? "Envoi…" : "Recevoir le code",
                disabled: phone.count < 9 || session.isWorking
            ) {
                let fullNumber = "+33\(phone.filter(\.isNumber))"
                Task { await session.sendPhoneCode(phoneNumber: fullNumber) }
                step = .codeEntry
            }
        }
        .pitchaCard()
    }

    // MARK: Étape 2 : code SMS

    private var codeEntryCard: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Code de vérification")
                    .font(.headline.weight(.heavy)).foregroundStyle(Pitcha.navy)
                Text("Saisis le code reçu par SMS.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField("123456", text: $code)
                .keyboardType(.numberPad)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.08)))

            PitchaButton(
                label: session.isWorking ? "Vérification…" : "Confirmer",
                disabled: code.count < 6 || session.isWorking
            ) {
                Task { await session.verifyPhoneCode(code: code) }
            }

            Button("Changer de numéro") { step = .phoneEntry; phone = ""; code = "" }
                .font(.footnote).foregroundStyle(Pitcha.tealDark)
        }
        .pitchaCard()
    }
}

// MARK: - Onboarding pseudo (nouvel utilisateur après phone auth)

struct OnboardingView: View {
    let uid: String
    @EnvironmentObject var session: SessionViewModel
    @State private var pseudo = ""
    @State private var agreed = false

    var body: some View {
        ZStack {
            PitchaBackground()
            VStack(spacing: 28) {
                VStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 56)).foregroundStyle(Pitcha.gradient)
                    Text("Crée ton profil")
                        .font(.title2.weight(.heavy)).foregroundStyle(Pitcha.navy)
                    Text("Choisis ton pseudo Pitcha.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 50)

                VStack(spacing: 18) {
                    PitchaTextField(icon: "tag.fill", placeholder: "Pseudo (ex : Adil_10)", text: $pseudo)

                    Toggle(isOn: $agreed) {
                        Text("J'accepte les conditions d'utilisation")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .tint(Pitcha.teal)

                    if let error = session.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }

                    PitchaButton(
                        label: session.isWorking ? "Création…" : "Commencer",
                        disabled: pseudo.count < 3 || !agreed || session.isWorking
                    ) {
                        Task { await session.registerPseudo(uid: uid, pseudo: pseudo) }
                    }
                }
                .pitchaCard()

                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Helpers UI partagés

private extension View {
    func pitchaCard() -> some View {
        self.padding(22)
            .background(RoundedRectangle(cornerRadius: 26).fill(.white)
                .shadow(color: .black.opacity(0.07), radius: 12, y: 6))
    }
}

struct PitchaButton: View {
    let label: String
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).fontWeight(.bold).frame(maxWidth: .infinity).frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 16)
                    .fill(disabled ? AnyShapeStyle(Color.gray.opacity(0.25)) : AnyShapeStyle(Pitcha.gradient)))
                .foregroundStyle(disabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.white))
        }
        .disabled(disabled)
    }
}
