import SwiftUI

struct AuthView: View {
    @EnvironmentObject var session: SessionViewModel

    @State private var isSignUp = false
    @State private var pseudo = ""
    @State private var email = ""
    @State private var password = ""

    private var formIsValid: Bool {
        let emailOK = email.contains("@") && email.contains(".")
        let passwordOK = password.count >= 6
        let pseudoOK = isSignUp ? pseudo.trimmingCharacters(in: .whitespaces).count >= 3 : true
        return emailOK && passwordOK && pseudoOK
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.teal.opacity(0.25), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Logo
                VStack(spacing: 8) {
                    Image(systemName: "soccerball.inverse")
                        .font(.system(size: 64))
                        .foregroundStyle(.teal)
                    Text("Pitcha")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                    Text("Joue. Progresse. Domine.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Formulaire
                VStack(spacing: 14) {
                    if isSignUp {
                        PitchaTextField(icon: "person.fill", placeholder: "Pseudo", text: $pseudo)
                    }
                    PitchaTextField(icon: "envelope.fill", placeholder: "Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    PitchaTextField(icon: "lock.fill", placeholder: "Mot de passe (6 min.)", text: $password, isSecure: true)
                }
                .padding(.horizontal, 24)

                if let error = session.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Bouton principal
                Button {
                    Task {
                        if isSignUp {
                            await session.signUp(email: email, password: password, pseudo: pseudo)
                        } else {
                            await session.signIn(email: email, password: password)
                        }
                    }
                } label: {
                    Group {
                        if session.isWorking {
                            ProgressView().tint(.white)
                        } else {
                            Text(isSignUp ? "Créer mon compte" : "Se connecter")
                                .fontWeight(.bold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(formIsValid ? Color.teal : Color.gray.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(!formIsValid || session.isWorking)
                .padding(.horizontal, 24)

                // Bascule connexion / inscription
                Button {
                    withAnimation(.snappy) {
                        isSignUp.toggle()
                        session.errorMessage = nil
                    }
                } label: {
                    Text(isSignUp ? "Déjà un compte ? **Se connecter**" : "Pas de compte ? **S'inscrire**")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }

                Spacer()
            }
        }
    }
}

// MARK: - Écran vérification email

struct EmailVerificationView: View {
    @EnvironmentObject var session: SessionViewModel
    @State private var emailResent = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 64))
                .foregroundStyle(.teal)

            Text("Vérifie ton email")
                .font(.title.bold())

            Text("Un lien de vérification t'a été envoyé.\nClique dessus puis reviens ici.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let error = session.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                Task { await session.checkEmailVerified() }
            } label: {
                Group {
                    if session.isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text("J'ai vérifié mon email").fontWeight(.bold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.teal)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 24)

            Button {
                Task {
                    await session.resendVerificationEmail()
                    emailResent = true
                }
            } label: {
                Text(emailResent ? "Email renvoyé ✓" : "Renvoyer l'email")
                    .font(.subheadline)
            }

            Button("Se déconnecter", role: .destructive) {
                session.signOut()
            }
            .font(.footnote)

            Spacer()
        }
    }
}

// MARK: - Composant champ texte

struct PitchaTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.teal)
                .frame(width: 24)
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .autocorrectionDisabled()
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
