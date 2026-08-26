import SwiftUI

struct AuthView: View {
    @EnvironmentObject var session: SessionViewModel
    @State private var isLogin = true
    @State private var email = ""
    @State private var password = ""
    @State private var pseudo = ""
    @State private var selectedGender: Gender?
    @State private var selectedCity: String?
    @State private var selectedPosition: PlayerPosition?
    @State private var referralCode = ""
    @State private var showReset = false
    @State private var showTerms = false
    @State private var showPrivacy = false

    var body: some View {
        ZStack {
            PitchaBackground()

            // Décor diagonal en bas, en écho à celui d'en haut à droite
            // (PitchaBackground), pour équilibrer l'écran qui était vide
            // en bas.
            GeometryReader { geo in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geo.size.height))
                    path.addLine(to: CGPoint(x: geo.size.width * 0.5, y: geo.size.height))
                    path.addLine(to: CGPoint(x: 0, y: geo.size.height * 0.62))
                    path.closeSubpath()
                }
                .fill(Pitcha.mint.opacity(0.10))

                Path { path in
                    path.move(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.75))
                    path.addLine(to: CGPoint(x: 0, y: geo.size.height * 0.93))
                    path.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(.white.opacity(0.5))
            }
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    // Logo
                    VStack(spacing: 4) {
                        Image("PitchaLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                        Text("Jouez, Gagnez, Recommencez.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.top, 50)

                    // Carte formulaire
                    VStack(spacing: 18) {
                        // Toggle Connexion / Inscription
                        HStack(spacing: 0) {
                            ForEach(["Connexion", "Inscription"], id: \.self) { label in
                                Button {
                                    withAnimation(.snappy) { isLogin = label == "Connexion" }
                                } label: {
                                    Text(label)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(
                                            (isLogin && label == "Connexion") ||
                                            (!isLogin && label == "Inscription")
                                            ? Pitcha.tealDark : .secondary
                                        )
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            (isLogin && label == "Connexion") ||
                                            (!isLogin && label == "Inscription")
                                            ? Pitcha.teal.opacity(0.12) : Color.clear
                                        )
                                }
                            }
                        }
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Champs
                        if !isLogin {
                            PitchaTextField(icon: "person.fill", placeholder: "Pseudo", text: $pseudo)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Sexe")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    ForEach(Gender.allCases) { gender in
                                        Button {
                                            selectedGender = gender
                                        } label: {
                                            Text(gender.rawValue)
                                                .font(.subheadline.bold())
                                                .foregroundStyle(selectedGender == gender ? .white : Pitcha.navy)
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 40)
                                                .background(
                                                    Capsule().fill(
                                                        selectedGender == gender
                                                            ? AnyShapeStyle(Pitcha.gradient)
                                                            : AnyShapeStyle(Color.black.opacity(0.06))
                                                    )
                                                )
                                        }
                                    }
                                }
                                Text("Non modifiable après l'inscription.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Ville")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Menu {
                                    ForEach(MatchsViewModel.cities, id: \.self) { city in
                                        Button(city) { selectedCity = city }
                                    }
                                } label: {
                                    HStack {
                                        Text(selectedCity ?? "Choisis ta ville")
                                            .foregroundStyle(selectedCity == nil ? .secondary : Pitcha.navy)
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 14)
                                    .frame(height: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.black.opacity(0.06))
                                    )
                                }
                                Text("Sert à te classer avec les joueurs de ta région.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Poste")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    ForEach(PlayerPosition.allCases.filter { $0 != .gar }) { position in
                                        Button {
                                            selectedPosition = position
                                        } label: {
                                            Text(position.rawValue)
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(selectedPosition == position ? .white : Pitcha.navy)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(
                                                            selectedPosition == position
                                                                ? AnyShapeStyle(Pitcha.gradient)
                                                                : AnyShapeStyle(Color.black.opacity(0.06))
                                                        )
                                                )
                                        }
                                    }
                                }
                                Text("Non modifiable après l'inscription.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        PitchaTextField(icon: "envelope.fill", placeholder: "Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        PitchaSecureField(placeholder: "Mot de passe", text: $password, isNewPassword: !isLogin)

                        if !isLogin {
                            PitchaTextField(icon: "person.badge.plus", placeholder: "Code de parrainage (optionnel)", text: $referralCode)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        // Erreur
                        if let error = session.errorMessage {
                            Text(error)
                                .font(.footnote).foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        // Bouton principal
                        Button {
                            Task {
                                if isLogin {
                                    await session.signIn(email: email, password: password)
                                } else if let gender = selectedGender, let city = selectedCity, let position = selectedPosition {
                                    await session.signUp(email: email, password: password, pseudo: pseudo, gender: gender, city: city, position: position)
                                    // Parrainage optionnel : tentative silencieuse après
                                    // l'inscription — un code invalide ne doit jamais
                                    // bloquer la création de compte.
                                    let code = referralCode.trimmingCharacters(in: .whitespaces)
                                    if !code.isEmpty {
                                        try? await FirebaseService.shared.claimReferral(referrerPseudo: code)
                                    }
                                }
                            }
                        } label: {
                            Group {
                                if session.isWorking {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(isLogin ? "Se connecter" : "Créer mon compte")
                                        .fontWeight(.bold)
                                }
                            }
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(formValid ? Pitcha.gradient : LinearGradient(colors: [.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                            )
                            .foregroundStyle(formValid ? .white : .secondary)
                        }
                        .disabled(!formValid || session.isWorking)

                        if isLogin {
                            Button("Mot de passe oublié ?") { showReset = true }
                                .font(.footnote).foregroundStyle(Pitcha.tealDark)
                        } else {
                            // Discret, visible uniquement à l'inscription
                            VStack(spacing: 2) {
                                Text("En créant un compte, tu acceptes nos")
                                HStack(spacing: 4) {
                                    Button("CGU") { showTerms = true }
                                        .underline()
                                    Text("et notre")
                                    Button("politique de confidentialité") { showPrivacy = true }
                                        .underline()
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(22)
                    .background(
                        RoundedRectangle(cornerRadius: 26)
                            .fill(.white)
                            .shadow(color: .black.opacity(0.07), radius: 12, y: 6)
                    )
                    .padding(.horizontal, 24)

                    Spacer(minLength: 40)
                }
            }
        }
        .sheet(isPresented: $showReset) {
            ResetPasswordView()
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTerms) { TermsOfServiceView() }
        .sheet(isPresented: $showPrivacy) { PrivacyPolicyView() }
        .alert(
            "Déconnecté",
            isPresented: Binding(
                get: { session.forcedLogoutMessage != nil },
                set: { if !$0 { session.forcedLogoutMessage = nil } }
            )
        ) {
            Button("OK") { session.forcedLogoutMessage = nil }
        } message: {
            Text(session.forcedLogoutMessage ?? "")
        }
    }

    private var formValid: Bool {
        let emailOk = email.contains("@") && email.contains(".")
        let passOk  = password.count >= 6
        if isLogin { return emailOk && passOk }
        return pseudo.count >= 3 && emailOk && passOk && selectedGender != nil && selectedCity != nil && selectedPosition != nil
    }
}

// MARK: - Vérification email

struct EmailVerificationView: View {
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        ZStack {
            PitchaBackground()
            VStack(spacing: 24) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Pitcha.gradient)
                Text("Vérifie ton email")
                    .font(.title2.weight(.heavy)).foregroundStyle(Pitcha.navy)
                Text("Un lien de vérification a été envoyé à ton adresse. Clique dessus puis reviens ici.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)

                VStack(spacing: 12) {
                    Button {
                        Task { await session.refreshVerification() }
                    } label: {
                        Text("J'ai vérifié mon email")
                            .fontWeight(.bold).frame(maxWidth: .infinity).frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Pitcha.gradient))
                            .foregroundStyle(.white)
                    }
                    Button {
                        Task { await session.resendVerificationEmail() }
                    } label: {
                        Text("Renvoyer l'email")
                            .font(.subheadline).foregroundStyle(Pitcha.tealDark)
                    }
                    Button("Se déconnecter") { session.signOut() }
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)

                if let error = session.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        }
    }
}

// MARK: - Réinitialisation mot de passe

struct ResetPasswordView: View {
    @EnvironmentObject var session: SessionViewModel
    @State private var email = ""
    @State private var sent = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if sent {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44)).foregroundStyle(.green)
                        Text("Email envoyé !")
                            .font(.headline).foregroundStyle(Pitcha.navy)
                        Text("Vérifie ta boîte mail pour réinitialiser ton mot de passe.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 16)
                } else {
                    Text("Entre ton adresse email et on t'envoie un lien de réinitialisation.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    PitchaTextField(icon: "envelope.fill", placeholder: "Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if let error = session.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    Button {
                        Task {
                            await session.sendPasswordReset(email: email)
                            sent = true
                        }
                    } label: {
                        Text("Envoyer le lien")
                            .fontWeight(.bold).frame(maxWidth: .infinity).frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 16)
                                .fill(email.contains("@") ? Pitcha.gradient : LinearGradient(colors: [.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing)))
                            .foregroundStyle(email.contains("@") ? .white : .secondary)
                    }
                    .disabled(!email.contains("@"))
                }
            }
            .padding(24)
            .navigationTitle("Mot de passe oublié")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Champ mot de passe

struct PitchaSecureField: View {
    let placeholder: String
    @Binding var text: String
    var isNewPassword: Bool = false
    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.subheadline).foregroundStyle(Pitcha.tealDark).frame(width: 20)
            Group {
                if isVisible {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .font(.subheadline)
            // Active les suggestions natives iOS : trousseau/Face ID pour se
            // connecter, générateur de mot de passe fort à l'inscription.
            .textContentType(isNewPassword ? .newPassword : .password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
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
