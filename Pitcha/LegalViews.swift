import SwiftUI

// MARK: - Politique de confidentialité

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Politique de confidentialité")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(Pitcha.navy)

                    Text("Dernière mise à jour : juin 2026")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    legalSection("1. Données collectées", """
Pitcha collecte les informations suivantes :
• Email et mot de passe (authentification)
• Pseudo, photo de profil (optionnelle)
• Statistiques de jeu (matchs, buts, victoires)
• Position approximative via les villes que tu sélectionnes
• Messages envoyés dans les chats d'équipe et privés
""")

                    legalSection("2. Utilisation des données", """
Ces données servent uniquement à faire fonctionner l'app : affichage de ton profil, classement, recherche d'amis, organisation de matchs. Elles ne sont jamais vendues à des tiers.
""")

                    legalSection("3. Stockage", """
Tes données sont stockées sur les serveurs de Google Firebase (Firestore), avec des règles d'accès strictes : seuls toi et les personnes avec qui tu joues peuvent voir tes informations de profil.
""")

                    legalSection("4. Tes droits", """
Tu peux à tout moment :
• Modifier ton profil
• Supprimer ton compte et toutes les données associées depuis l'app (Profil → Menu → Supprimer mon compte)
• Nous contacter pour toute question via le support
""")

                    legalSection("5. Contact", """
Pour toute question concernant tes données : support@pitcha.app
""")
                }
                .padding()
            }
            .background(Pitcha.background)
            .navigationTitle("Confidentialité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func legalSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline.weight(.heavy))
                .foregroundStyle(Pitcha.navy)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Conditions Générales d'Utilisation

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Conditions Générales d'Utilisation")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(Pitcha.navy)

                    Text("Dernière mise à jour : juin 2026")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    legalSection("1. Objet", """
Pitcha est une application permettant d'organiser des matchs de football amateur, de suivre ses statistiques et d'échanger avec d'autres joueurs.
""")

                    legalSection("2. Compte utilisateur", """
La création d'un compte nécessite un email valide. Tu es responsable de la confidentialité de ton mot de passe et de toute activité effectuée depuis ton compte.
""")

                    legalSection("3. Comportement attendu", """
En utilisant Pitcha, tu t'engages à :
• Ne pas harceler, insulter ou menacer d'autres utilisateurs
• Ne pas publier de contenu illégal, violent ou à caractère sexuel
• Ne pas usurper l'identité d'un autre joueur
• Respecter les horaires et engagements pris pour les matchs

Tout manquement peut entraîner la suspension ou la suppression de ton compte.
""")

                    legalSection("4. Signalement et modération", """
Tu peux signaler ou bloquer un utilisateur depuis son profil, un match ou une conversation. Les signalements sont examinés par l'équipe Pitcha.
""")

                    legalSection("5. Coins et achats", """
Les coins utilisés dans l'app n'ont aucune valeur monétaire réelle et ne sont pas remboursables.
""")

                    legalSection("6. Responsabilité", """
Pitcha facilite l'organisation de matchs mais n'est pas responsable des blessures, litiges ou incidents survenant lors de rencontres organisées via l'app. Joue prudemment et respecte les règles du fair-play.
""")

                    legalSection("7. Contact", """
Pour toute question : support@pitcha.app
""")
                }
                .padding()
            }
            .background(Pitcha.background)
            .navigationTitle("CGU")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func legalSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline.weight(.heavy))
                .foregroundStyle(Pitcha.navy)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Suppression de compte

struct DeleteAccountView: View {
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var showFinalConfirm = false
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.red)
                    Text("Supprimer ton compte")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Pitcha.navy)
                    Text("Cette action est définitive. Ton profil, tes statistiques et ton historique seront supprimés. Tu ne pourras pas récupérer ces données.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Confirme ton mot de passe")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Pitcha.navy)
                    PitchaSecureField(placeholder: "Mot de passe", text: $password)
                }

                if let error = session.deletionError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button(role: .destructive) {
                    showFinalConfirm = true
                } label: {
                    Group {
                        if isDeleting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Supprimer définitivement mon compte")
                                .fontWeight(.bold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(password.count >= 6 ? Color.red : Color.gray.opacity(0.3))
                    )
                    .foregroundStyle(.white)
                }
                .disabled(password.count < 6 || isDeleting)

                Spacer()
            }
            .padding(24)
            .background(Pitcha.background)
            .navigationTitle("Supprimer mon compte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                }
            }
            .confirmationDialog(
                "Es-tu vraiment sûr(e) ?",
                isPresented: $showFinalConfirm,
                titleVisibility: .visible
            ) {
                Button("Oui, supprimer définitivement", role: .destructive) {
                    Task {
                        isDeleting = true
                        let success = await session.deleteAccount(password: password)
                        isDeleting = false
                        if success { dismiss() }
                    }
                }
            } message: {
                Text("Il n'y a pas de retour en arrière possible.")
            }
        }
    }
}

// MARK: - Liste des comptes bloqués (gestion/déblocage)

struct BlockedUsersView: View {
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var blockedProfiles: [AppUser] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if blockedProfiles.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Aucun compte bloqué")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(blockedProfiles) { profile in
                                HStack(spacing: 12) {
                                    InitialsAvatar(text: profile.pseudo, size: 42, cornerStyle: .circle)
                                    Text(profile.pseudo)
                                        .font(.subheadline.weight(.heavy))
                                        .foregroundStyle(Pitcha.navy)
                                    Spacer()
                                    Button("Débloquer") {
                                        Task { await unblock(profile) }
                                    }
                                    .font(.caption.bold())
                                    .foregroundStyle(Pitcha.tealDark)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.white)
                                        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Pitcha.background)
            .navigationTitle("Comptes bloqués")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task { await loadBlocked() }
        }
    }

    private func loadBlocked() async {
        let uids = session.user?.blockedUids ?? []
        guard !uids.isEmpty else { isLoading = false; return }
        if let users = try? await FirebaseService.shared.fetchUsers(uids: uids) {
            blockedProfiles = users
        }
        isLoading = false
    }

    private func unblock(_ profile: AppUser) async {
        guard let myUid = session.user?.id, let targetUid = profile.id else { return }
        try? await FirebaseService.shared.setBlocked(myUid: myUid, targetUid: targetUid, blocked: false)
        blockedProfiles.removeAll { $0.id == targetUid }
    }
}

// MARK: - Sheet réutilisable : Signaler / Bloquer un utilisateur

struct ReportBlockSheet: View {
    let targetUid: String
    let targetPseudo: String
    let context: String       // "match", "team", "dm"
    let contextId: String?

    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showReportReasons = false
    @State private var showBlockConfirm = false
    @State private var isBlocked = false
    @State private var feedback: String?

    private let reasons = [
        "Comportement toxique / insultes",
        "Contenu inapproprié",
        "Usurpation d'identité",
        "Spam",
        "Autre"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    InitialsAvatar(text: targetPseudo, size: 60, cornerStyle: .circle)
                    Text(targetPseudo)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Pitcha.navy)
                }
                .padding(.top, 24)
                .padding(.bottom, 20)

                if let feedback {
                    Text(feedback)
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                        .padding(.bottom, 12)
                }

                VStack(spacing: 0) {
                    Button { showReportReasons = true } label: {
                        rowLabel("Signaler ce joueur", icon: "flag.fill", tint: .orange)
                    }
                    Divider().padding(.leading, 56)
                    Button { showBlockConfirm = true } label: {
                        rowLabel(
                            isBlocked ? "Débloquer ce joueur" : "Bloquer ce joueur",
                            icon: isBlocked ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.xmark",
                            tint: .red
                        )
                    }
                }
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
                .padding(.horizontal)

                Spacer()
            }
            .background(Pitcha.background)
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
            }
            .confirmationDialog("Pourquoi signales-tu ce joueur ?", isPresented: $showReportReasons, titleVisibility: .visible) {
                ForEach(reasons, id: \.self) { reason in
                    Button(reason) {
                        Task { await report(reason: reason) }
                    }
                }
            }
            .confirmationDialog(
                isBlocked ? "Débloquer \(targetPseudo) ?" : "Bloquer \(targetPseudo) ?",
                isPresented: $showBlockConfirm,
                titleVisibility: .visible
            ) {
                Button(isBlocked ? "Débloquer" : "Bloquer", role: isBlocked ? .none : .destructive) {
                    Task { await toggleBlock() }
                }
            } message: {
                Text(isBlocked
                     ? "Vous pourrez à nouveau interagir normalement."
                     : "Ses messages seront masqués et il ne pourra plus t'envoyer de demande d'ami.")
            }
            .task {
                isBlocked = session.user?.hasBlocked(targetUid) ?? false
            }
        }
    }

    private func rowLabel(_ label: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(tint).frame(width: 28)
            Text(label).font(.subheadline.bold()).foregroundStyle(Pitcha.navy)
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func report(reason: String) async {
        try? await FirebaseService.shared.reportUser(
            reportedId: targetUid,
            reportedPseudo: targetPseudo,
            reason: reason,
            context: context,
            contextId: contextId
        )
        feedback = "Signalement envoyé. Merci."
    }

    private func toggleBlock() async {
        guard let myUid = session.user?.id else { return }
        let newValue = !isBlocked
        try? await FirebaseService.shared.setBlocked(myUid: myUid, targetUid: targetUid, blocked: newValue)
        isBlocked = newValue
        feedback = newValue ? "\(targetPseudo) a été bloqué." : "\(targetPseudo) a été débloqué."
    }
}
