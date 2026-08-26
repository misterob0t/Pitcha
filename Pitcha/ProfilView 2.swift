import SwiftUI
import PhotosUI
import StoreKit
import FirebaseFirestore


struct ProfilView: View {
    @EnvironmentObject var session: SessionViewModel
    // Dépendance explicite : force SwiftUI à redessiner cette vue
    // (et tous ses enfants) dès que le Mode Filles est activé/désactivé.
    @StateObject private var viewModel = ProfilViewModel()
    @State private var historyMode: HistoryMode?
    @State private var showPasswordAlert = false
    @State private var showFriendRequests = false
    @State private var showPlayerInfo = false
    @State private var showPrivacyPolicy = false
    @State private var showTerms = false
    @State private var showDeleteAccount = false
    @State private var showBlockedUsers = false
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        Group {
            if let user = session.user {
                // Contenu enveloppé dans un ScrollView défensif : la page est
                // pensée pour tenir sans scroll, mais si le contenu dépasse
                // parfois la hauteur d'écran (ex: badge fiabilité, MVP, série
                // en cours qui s'ajoutent), ça absorbe le débordement au lieu
                // de perturber la position de la tab bar personnalisée.
                ScrollView {
                VStack(spacing: 12) {
                    // Header : cloche + menu
                    HStack {
                        ZStack(alignment: .topTrailing) {
                            CircleIconButton(icon: "bell") { showFriendRequests = true }
                            if !(session.user?.incomingRequests.isEmpty ?? true) || !session.pendingMatchInvites.isEmpty {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 10, height: 10)
                                    .offset(x: 2, y: -2)
                            }
                        }
                        CircleIconButton(icon: "person") { showPlayerInfo = true }
                        Spacer()
                        Menu {
                            Button {
                                requestReview()
                            } label: {
                                Label("Notez-nous", systemImage: "star.fill")
                            }
                            Button {
                                Task {
                                    await viewModel.sendPasswordReset(email: user.email)
                                    showPasswordAlert = true
                                }
                            } label: {
                                Label("Changer mot de passe", systemImage: "key.fill")
                            }
                            Divider()
                            Button {
                                showPrivacyPolicy = true
                            } label: {
                                Label("Politique de confidentialité", systemImage: "hand.raised.fill")
                            }
                            Button {
                                showTerms = true
                            } label: {
                                Label("Conditions d'utilisation", systemImage: "doc.text.fill")
                            }
                            Button {
                                showBlockedUsers = true
                            } label: {
                                Label("Comptes bloqués", systemImage: "person.crop.circle.badge.xmark")
                            }
                            Divider()
                            Button(role: .destructive) {
                                session.signOut()
                            } label: {
                                Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                            Button(role: .destructive) {
                                showDeleteAccount = true
                            } label: {
                                Label("Supprimer mon compte", systemImage: "trash.fill")
                            }
                        } label: {
                            CircleIconLabel(icon: "line.3.horizontal")
                        }
                    }
                    .padding(.horizontal)

                    // Bandeau niveau — purement informatif désormais (plus
                    // de distribution de points, l'XP ne vient que du Classé)
                    LevelBanner(user: user)
                        .padding(.horizontal)

                    Spacer(minLength: 0)
                        .frame(maxHeight: 22)

                    // Carte FIFA (largeur carte, pas pleine largeur)
                    FlippablePlayerCard(user: user, viewModel: viewModel)
                        .frame(maxWidth: 300)

                    Spacer(minLength: 0)
                        .frame(maxHeight: 22)

                    // Stats (cliquables -> historique)
                    HStack(spacing: 12) {
                        Button { historyMode = .chrono } label: {
                            StatCard(icon: "sportscourt.fill", value: "\(user.totalMatches)")
                        }
                        Button { historyMode = .topScorer } label: {
                            StatCard(icon: "soccerball.inverse", value: "\(user.totalGoals)", accent: true)
                        }
                        Button { historyMode = .results } label: {
                            StatCard(icon: "chart.bar.fill", value: "\(user.totalWins)/\(user.totalDraws)/\(user.totalLosses)")
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 14)
                .padding(.bottom, 28)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(PitchaBackground())
        .sheet(item: $historyMode) { mode in
            MatchHistorySheet(mode: mode, viewModel: viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFriendRequests) {
            FriendRequestsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPlayerInfo) {
            PlayerInfoSheet(viewModel: viewModel)
                .presentationDetents([.height(580)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPrivacyPolicy) { PrivacyPolicyView() }
        .sheet(isPresented: $showTerms) { TermsOfServiceView() }
        .sheet(isPresented: $showDeleteAccount) { DeleteAccountView() }
        .sheet(isPresented: $showBlockedUsers) { BlockedUsersView() }
        .alert("Email envoyé", isPresented: $showPasswordAlert) {
            Button("OK") {}
        } message: {
            Text("Un lien pour changer ton mot de passe a été envoyé à ton adresse email.")
        }
        .sensoryFeedback(.success, trigger: viewModel.saveSucceeded)
    }
}

// MARK: - Boutons ronds header

struct CircleIconButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CircleIconLabel(icon: icon)
        }
    }
}

struct CircleIconLabel: View {
    let icon: String

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Pitcha.tealDark)
            .frame(width: 48, height: 48)
            .background(Circle().fill(.white))
            .shadow(color: .black.opacity(0.07), radius: 8, y: 4)
    }
}

// MARK: - Bandeau niveau (tappable -> skill points)

struct LevelBanner: View {
    let user: AppUser

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("NIVEAU \(user.level)")
                    .font(.title3.weight(.heavy))
                Text(user.levelTitle)
                    .font(.caption)
                    .opacity(0.8)
            }

            // Barre d'XP orange (progression réelle via les seuils)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.25))
                    Capsule()
                        .fill(Pitcha.goldGradient)
                        .frame(width: max(12, geo.size.width * user.levelProgress))
                        .animation(.snappy, value: user.levelProgress)
                }
            }
            .frame(height: 11)

            HStack {
                Text("\(user.xp) XP")
                    .font(.caption.bold())
                    .monospacedDigit()
                Spacer()
                if user.xpToNext > 0 {
                    Text("\(user.xpToNext) XP avant le niveau \(user.level + 1)")
                        .font(.caption2.bold())
                }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Pitcha.gradient)
                .shadow(color: Pitcha.teal.opacity(0.35), radius: 10, y: 5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }
}

// MARK: - Carte avec flip recto/verso

struct FlippablePlayerCard: View {
    let user: AppUser
    @ObservedObject var viewModel: ProfilViewModel

    @State private var isFlipped = false
    @State private var degree = 0.0          // rotation du flip (Y, par paliers de 180°)
    @State private var tiltX: Double = 0     // inclinaison verticale au glissement (X)
    @State private var tiltY: Double = 0     // inclinaison horizontale au glissement (Y)
    @State private var dragLocation: CGPoint = .zero
    @State private var cardSize: CGSize = .zero
    @State private var isDragging = false

    var body: some View {
        ZStack {
            FifaCardFront(user: user, viewModel: viewModel)
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(.degrees(degree + tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.4)

            FifaCardBack(user: user, viewModel: viewModel)
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(degree + 180 + tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
        }
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { cardSize = geo.size }
            }
        )
        // Un seul geste gère à la fois le tap (flip) et le glisser (tilt) :
        // SwiftUI n'arbitre pas toujours bien .gesture + .onTapGesture combinés,
        // donc on détecte nous-mêmes si le mouvement est un tap (quasi immobile)
        // ou un vrai glissement.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    dragLocation = value.location
                    guard cardSize.width > 0, cardSize.height > 0 else { return }
                    let relativeX = (value.location.x / cardSize.width) - 0.5
                    let relativeY = (value.location.y / cardSize.height) - 0.5
                    withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.7)) {
                        tiltY = relativeX * 28   // inclinaison gauche/droite
                        tiltX = -relativeY * 22  // inclinaison haut/bas (inversée)
                    }
                }
                .onEnded { value in
                    isDragging = false
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        tiltX = 0
                        tiltY = 0
                    }
                    // Mouvement quasi immobile = on considère ça comme un tap -> flip
                    let distance = (value.translation.width * value.translation.width
                                   + value.translation.height * value.translation.height
                                   ).squareRoot()
                    if distance < 10 {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            degree += 180
                            isFlipped.toggle()
                        }
                    }
                }
        )
    }
}

// MARK: - Forme FIFA Ultimate Team (coins haut coupés, coins bas arrondis)

struct FIFACardShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let cornerCut: CGFloat = 25   // taille des coins coupés en haut
        let bottomRadius: CGFloat = 16 // arrondi en bas

        path.move(to: CGPoint(x: 0, y: rect.height - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: bottomRadius, y: rect.height),
            control: CGPoint(x: 0, y: rect.height)
        )
        path.addLine(to: CGPoint(x: rect.width - bottomRadius, y: rect.height))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.height - bottomRadius),
            control: CGPoint(x: rect.width, y: rect.height)
        )
        path.addLine(to: CGPoint(x: rect.width, y: cornerCut))
        path.addLine(to: CGPoint(x: rect.width - cornerCut, y: 0))
        path.addLine(to: CGPoint(x: cornerCut, y: 0))
        path.addLine(to: CGPoint(x: 0, y: cornerCut))
        path.closeSubpath()

        return path
    }
}

// MARK: - Recto : carte Classé (division + PL) — devenue la seule
// identité de la carte, l'ancien recto avec VIT/TIR/PAS/etc a été retiré.

struct FifaCardFront: View {
    let user: AppUser
    @ObservedObject var viewModel: ProfilViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var shimmerOffset: CGFloat = -1.0
    @State private var showingTitleEdit = false
    @State private var newTitle = ""

    // Couleurs extraites (allège le type-checking)
    private static let greenStops: [Color] = [
        Color(hex: "0D4D3A"), Color(hex: "156B4D"), Color(hex: "1A8D5F"),
        Color(hex: "156B4D"), Color(hex: "0D4D3A")
    ]
    private static let goldStops: [Gradient.Stop] = [
        .init(color: Color(hex: "D4AF37").opacity(0.9), location: 0.0),
        .init(color: Color(hex: "FFD700"), location: 0.2),
        .init(color: Color(hex: "D4AF37").opacity(0.6), location: 0.4),
        .init(color: Color(hex: "FFD700").opacity(0.8), location: 0.6),
        .init(color: Color(hex: "D4AF37"), location: 0.8),
        .init(color: Color(hex: "FFD700").opacity(0.9), location: 1.0)
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            photoAndName
            plProgressBar
        }
        .background(cardBackground)
        .clipShape(FIFACardShape())
        .overlay(cardBorder)
        .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
        .shadow(color: Color(hex: "0F766E").opacity(0.4), radius: 30, x: 0, y: 15)
        .shadow(color: Color(hex: "D4AF37").opacity(0.15), radius: 40, x: 0, y: 5)
        .onAppear {
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 1.0
            }
        }
    }

    // MARK: En-tête : poste (verrouillé) + division Classé

    private var headerRow: some View {
        HStack {
            // Poste : figé depuis l'inscription, plus modifiable depuis la carte.
            Text(user.position.rawValue)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        )
                )

            Spacer()

            divisionBadge
        }
        .padding()
    }

    private var divisionBadge: some View {
        VStack(spacing: 5) {
            ZStack {
                if let division = user.rankedDivisionEnum {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: division.tierColors,
                                center: .center,
                                startRadius: 5,
                                endRadius: 25
                            )
                        )
                        .frame(width: 50, height: 50)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .shadow(color: (division.tierColors.first ?? .gray).opacity(0.5), radius: 8)

                    Text(division.shortCode)
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.7), radius: 2)
                } else {
                    // Non classé : grisé, pas d'effet lumineux
                    Circle()
                        .fill(Color.gray.opacity(0.35))
                        .frame(width: 50, height: 50)
                        .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))

                    Text("NC")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(.white.opacity(0.75))
                }
            }

            if user.hasPremium {
                HStack(spacing: 3) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("PREMIUM")
                        .font(.system(size: 7, weight: .heavy))
                        .kerning(0.5)
                }
                .foregroundStyle(Color(hex: "D4AF37"))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.35))
                        .overlay(
                            Capsule()
                                .stroke(Color(hex: "D4AF37").opacity(0.6), lineWidth: 0.8)
                        )
                )
            }
        }
    }

    // MARK: Photo + nom

    private var photoAndName: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                photoCircle
            }
            .onChange(of: photoItem) { _, newItem in
                Task {
                    guard let newItem,
                          let data = try? await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    await viewModel.savePhoto(image, user: user)
                }
            }

            VStack(spacing: 4) {
                Text(user.pseudo)
                    .font(.title2)
                    .fontWeight(.black)
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.7), radius: 3)

                // Titre style League of Legends (tap = modifier)
                Button {
                    newTitle = user.title ?? ""
                    showingTitleEdit = true
                } label: {
                    if let title = user.title, !title.isEmpty {
                        Text(title.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .kerning(2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "FFD700"), Color(hex: "D4AF37")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: Color.black.opacity(0.5), radius: 2)
                    } else {
                        Text("Ajouter un titre")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .italic()
                    }
                }

                if let nickname = user.nickname, !nickname.isEmpty {
                    Text(nickname)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .italic()
                        .shadow(color: Color.black.opacity(0.5), radius: 2)
                }
            }
        }
        .alert("Ton titre", isPresented: $showingTitleEdit) {
            TextField("Ex : Le Magicien des Surfaces", text: $newTitle)
            Button("Annuler", role: .cancel) {}
            Button("OK") {
                Task { await viewModel.saveTitle(newTitle, user: user) }
            }
        } message: {
            Text("Affiché sous ton pseudo, comme dans League of Legends.")
        }
    }

    private var photoCircle: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.3),
                                Color.clear,
                                Color.black.opacity(0.3)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 130, height: 130)

                photoContent
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white,
                                        Color.white.opacity(0.5),
                                        Color.clear
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    )
            }

            // Badge discret indiquant que la photo est modifiable — visible
            // uniquement tant qu'aucune photo personnalisée n'a été ajoutée.
            if user.photoURL == nil {
                ZStack {
                    Circle()
                        .fill(Pitcha.teal)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .offset(x: -4, y: -4)
            }
        }
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
    }

    private var photoContent: some View {
        AvatarImage(user: user, size: 120)
            .clipShape(Circle())
    }

    // MARK: Stats

    private var plProgressBar: some View {
        let division = user.rankedDivisionEnum
        let colors = division?.tierColors ?? [Color.gray, Color.gray.opacity(0.6)]
        let ratio: CGFloat = division != nil
            ? CGFloat(min(user.rankedPLValue, 99)) / 100.0
            : CGFloat(user.rankedPlacementsPlayedValue) / CGFloat(RankedSystem.placementMatchesRequired)

        return VStack(spacing: 6) {
            HStack {
                Text(division?.displayName.uppercased() ?? "NON CLASSÉ")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                if division != nil {
                    Text("\(user.rankedPLValue) PL")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.white.opacity(0.85))
                        .contentTransition(.numericText())
                } else {
                    Text("Placement \(user.rankedPlacementsPlayedValue)/\(RankedSystem.placementMatchesRequired)")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.white.opacity(0.85))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * ratio))
                        .animation(.snappy, value: ratio)
                }
            }
            .frame(height: 8)
        }
        .padding()
    }

    // MARK: Fond 4 couches

    private var cardBackground: some View {
        ZStack {
            // 1. Gradient principal vert FIFA
            LinearGradient(
                gradient: Gradient(colors: Self.greenStops),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 2. Pattern diagonal subtil
            diagonalPattern

            // 3. Reflet lumineux fixe
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.25),
                    Color.white.opacity(0.1),
                    Color.clear
                ]),
                center: UnitPoint(x: 0.2, y: 0.15),
                startRadius: 20,
                endRadius: 180
            )

            // 4. Shimmer animé
            shimmerLayer
        }
    }

    private var diagonalPattern: some View {
        GeometryReader { geo in
            Path { path in
                let spacing: CGFloat = 20
                for i in stride(from: -geo.size.height, to: geo.size.width + geo.size.height, by: spacing) {
                    path.move(to: CGPoint(x: i, y: 0))
                    path.addLine(to: CGPoint(x: i - geo.size.height, y: geo.size.height))
                }
            }
            .stroke(Color.white.opacity(0.03), lineWidth: 1)
        }
    }

    private var shimmerLayer: some View {
        GeometryReader { geo in
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.clear,
                    Color.white.opacity(0.15),
                    Color.white.opacity(0.25),
                    Color.white.opacity(0.15),
                    Color.clear
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: geo.size.width * 0.6)
            .offset(x: geo.size.width * shimmerOffset)
            .blur(radius: 15)
        }
        .mask(FIFACardShape())
    }

    // MARK: Bordures

    private var cardBorder: some View {
        ZStack {
            FIFACardShape()
                .stroke(
                    LinearGradient(
                        gradient: Gradient(stops: Self.goldStops),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )

            FIFACardShape()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .padding(4)

            cornerLines
        }
    }

    private var cornerLines: some View {
        VStack {
            HStack {
                Path { path in
                    path.move(to: CGPoint(x: 8, y: 28))
                    path.addLine(to: CGPoint(x: 28, y: 8))
                }
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "FFD700"), Color(hex: "D4AF37")],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 30, height: 30)

                Spacer()

                Path { path in
                    path.move(to: CGPoint(x: 2, y: 8))
                    path.addLine(to: CGPoint(x: 22, y: 28))
                }
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "D4AF37"), Color(hex: "FFD700")],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 30, height: 30)
            }

            Spacer()
        }
        .padding(6)
    }
}

// MARK: - Verso : bilan de saison Classé

struct FifaCardBack: View {
    let user: AppUser
    @ObservedObject var viewModel: ProfilViewModel
    @State private var shimmerOffset: CGFloat = -1.0

    private static let greenStops: [Color] = [
        Color(hex: "0D4D3A"), Color(hex: "156B4D"), Color(hex: "1A8D5F"),
        Color(hex: "156B4D"), Color(hex: "0D4D3A")
    ]
    private static let goldStops: [Gradient.Stop] = [
        .init(color: Color(hex: "D4AF37").opacity(0.9), location: 0.0),
        .init(color: Color(hex: "FFD700"), location: 0.2),
        .init(color: Color(hex: "D4AF37").opacity(0.6), location: 0.4),
        .init(color: Color(hex: "FFD700").opacity(0.8), location: 0.6),
        .init(color: Color(hex: "D4AF37"), location: 0.8),
        .init(color: Color(hex: "FFD700").opacity(0.9), location: 1.0)
    ]

    var body: some View {
        VStack(spacing: 18) {
            Text("BILAN DE SAISON")
                .font(.subheadline.weight(.heavy))
                .kerning(2)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 26)

            // Record classé V/N/D
            HStack(spacing: 10) {
                SeasonStatPill(value: "\(user.rankedWinsValue)", label: "V", color: .green)
                SeasonStatPill(value: "\(user.rankedDrawsValue)", label: "N", color: .white.opacity(0.7))
                SeasonStatPill(value: "\(user.rankedLossesValue)", label: "D", color: .red)
            }

            VStack(spacing: 14) {
                BackInfoRow(icon: "trophy.fill") {
                    Text("Meilleure division")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    if let best = user.bestDivisionReachedEnum {
                        Text(best.displayName)
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(.white)
                    } else {
                        Text("—")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                BackInfoRow(icon: "flame.fill") {
                    Text("Série en cours")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text(user.streakDescription ?? "Aucune")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(.white)
                }

                BackInfoRow(icon: "star.fill") {
                    Text("Élu MVP")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text("\(user.mvpCountValue)×")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 22)

            Spacer()

            Text("Le bilan de saison ne compte que les matchs Classé.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBackground)
        .clipShape(FIFACardShape())
        .overlay(cardBorder)
        .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
        .shadow(color: Color(hex: "0F766E").opacity(0.4), radius: 30, x: 0, y: 15)
        .shadow(color: Color(hex: "D4AF37").opacity(0.15), radius: 40, x: 0, y: 5)
        .onAppear {
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 1.0
            }
        }
    }

    private var cardBackground: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: Self.greenStops), startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                gradient: Gradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.1), Color.clear]),
                center: UnitPoint(x: 0.2, y: 0.15), startRadius: 20, endRadius: 180
            )
            GeometryReader { geo in
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .white.opacity(0.15), .white.opacity(0.25), .white.opacity(0.15), .clear]),
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(width: geo.size.width * 0.6)
                .offset(x: geo.size.width * shimmerOffset)
                .blur(radius: 15)
            }
            .mask(FIFACardShape())
        }
    }

    private var cardBorder: some View {
        FIFACardShape()
            .stroke(
                LinearGradient(gradient: Gradient(stops: Self.goldStops), startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 3
            )
    }
}

// MARK: - Composants du bilan de saison

struct SeasonStatPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(color)
        }
        .frame(width: 58, height: 58)
        .background(Circle().fill(Color.black.opacity(0.25)))
        .overlay(Circle().stroke(color.opacity(0.5), lineWidth: 1.5))
    }
}

struct BackInfoRow<Content: View>: View {
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "F2C740"))
                .frame(width: 20)
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1)))
    }
}

// MARK: - Carte de stat

struct StatCard: View {
    let icon: String
    let value: String
    var accent = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(accent ? Pitcha.mint : Pitcha.tealDark)
            Text(value)
                .font(.headline.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(accent ? Pitcha.mint : Pitcha.tealDark)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        )
    }
}

// MARK: - Historique des matchs (3 modes selon la stat tapée)

// MARK: - Sheet Infos joueur — identité + fiabilité, séparée de la carte
// (le problème que ça règle : la carte mesure la progression/l'investissement,
// pas le niveau réel. Cette sheet, elle, montre qui est la personne.)

struct PlayerInfoSheet: View {
    @ObservedObject var viewModel: ProfilViewModel
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var ageDraft: Int = 18
    @State private var heightCm: Int = 175
    @State private var weightKg: Int = 70
    @State private var favoriteTeam = ""
    @State private var strongFoot: StrongFoot = .droit
    @State private var showTeamPicker = false

    /// Anime l'entrée des tuiles en cascade, sans jamais nécessiter de scroll.
    @State private var appeared = false
    @State private var justSavedAll = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if let user = session.user {
                    heroHeader(user: user)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : -10)

                    tilesGrid(user: user)

                    saveButton(user: user)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .onAppear {
                if let user = session.user {
                    ageDraft = user.age ?? 18
                    heightCm = user.heightCm ?? 175
                    weightKg = user.weightKg ?? 70
                    favoriteTeam = user.favoriteTeam ?? ""
                    strongFoot = user.strongFoot ?? .droit
                }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    appeared = true
                }
            }
            .background(Pitcha.background.ignoresSafeArea())
            .navigationTitle("Infos joueur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            .sheet(isPresented: $showTeamPicker) {
                FavoriteTeamPickerSheet(selectedTeam: $favoriteTeam)
            }
        }
    }

    // MARK: - Bouton Enregistrer (sauvegarde tout d'un coup : âge + infos physiques)

    private func saveButton(user: AppUser) -> some View {
        Button {
            Task {
                await viewModel.saveAge(ageDraft, user: user)
                await viewModel.savePersonalInfo(
                    user: user, heightCm: heightCm, weightKg: weightKg,
                    favoriteTeam: favoriteTeam, strongFoot: strongFoot
                )
                justSavedAll = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { justSavedAll = false }
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isWorking {
                    ProgressView().tint(.white)
                } else if justSavedAll {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Enregistré").font(.subheadline.weight(.heavy))
                } else {
                    Text("Enregistrer").font(.subheadline.weight(.heavy))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Capsule().fill(justSavedAll ? AnyShapeStyle(Color.green) : AnyShapeStyle(Pitcha.gradient)))
            .foregroundStyle(.white)
        }
        .disabled(viewModel.isWorking)
        .animation(.snappy, value: justSavedAll)
        .padding(.top, 2)
    }

    // MARK: - Hero header (identité)

    private func heroHeader(user: AppUser) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [Pitcha.navy, Color(hex: "1E3A5F")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            HStack(spacing: 12) {
                AvatarImage(user: user, size: 46)
                    .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(user.pseudo)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.white)
                    if let city = user.city {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.circle.fill").font(.caption2)
                            Text(city).font(.caption)
                        }
                        .foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer()
                if user.hasPremium {
                    Image(systemName: "crown.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "F2C740"))
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 68)
    }

    // MARK: - Bandeau parrainage (compact, une ligne)

    // MARK: - Grille de tuiles (2 colonnes, tient sur un seul écran)

    private func tilesGrid(user: AppUser) -> some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        let tiles = buildTiles(user: user)

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                tile
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.85)
                    .animation(
                        .spring(response: 0.45, dampingFraction: 0.75)
                        .delay(Double(index) * 0.04),
                        value: appeared
                    )
            }
        }
    }

    private func buildTiles(user: AppUser) -> [InfoTile] {
        [
            InfoTile(id: "position", icon: "figure.soccer", color: Pitcha.teal,
                     label: "Position", value: user.position.label),

            InfoTile(id: "age", icon: "birthday.cake.fill", color: .orange,
                     label: "Âge", value: "\(ageDraft) ans",
                     editContent: AnyView(
                        Menu {
                            ForEach(13...80, id: \.self) { age in
                                Button("\(age) ans") { ageDraft = age }
                            }
                        } label: { Color.clear.contentShape(Rectangle()) }
                     )),

            InfoTile(id: "reliability", icon: "hand.thumbsup.fill", color: .green,
                     label: "Fiabilité",
                     value: user.reliabilityAverage.map { String(format: "%.1f ★", $0) } ?? "—"),

            InfoTile(id: "height", icon: "ruler", color: .purple,
                     label: "Taille", value: "\(heightCm) cm",
                     editContent: AnyView(
                        Menu {
                            ForEach(Array(stride(from: 140, through: 220, by: 1)), id: \.self) { h in
                                Button("\(h) cm") { heightCm = h }
                            }
                        } label: { Color.clear.contentShape(Rectangle()) }
                     )),

            InfoTile(id: "weight", icon: "scalemass", color: .pink,
                     label: "Poids", value: "\(weightKg) kg",
                     editContent: AnyView(
                        Menu {
                            ForEach(Array(stride(from: 40, through: 150, by: 1)), id: \.self) { w in
                                Button("\(w) kg") { weightKg = w }
                            }
                        } label: { Color.clear.contentShape(Rectangle()) }
                     )),

            InfoTile(id: "gender", icon: "person.fill", color: Pitcha.tealDark,
                     label: "Sexe", value: user.gender ?? "—"),

            InfoTile(id: "team", icon: "heart.fill", color: .red,
                     label: "Équipe favorite", value: favoriteTeam.isEmpty ? "Choisir" : favoriteTeam,
                     editContent: AnyView(
                        Button { showTeamPicker = true } label: { Color.clear.contentShape(Rectangle()) }
                     )),

            InfoTile(id: "foot", icon: "shoe.2.fill", color: .indigo,
                     label: "Pied fort", value: strongFoot.rawValue,
                     editContent: AnyView(
                        Menu {
                            ForEach(StrongFoot.allCases) { foot in
                                Button(foot.rawValue) { strongFoot = foot }
                            }
                        } label: { Color.clear.contentShape(Rectangle()) }
                     ))
        ]
    }
}

// MARK: - Tuile d'info animée (lecture seule ou éditable via menu)

struct InfoTile: View {
    let id: String
    let icon: String
    let color: Color
    let label: String
    let value: String
    var editContent: AnyView = AnyView(EmptyView())

    @State private var isPressed = false

    init(
        id: String, icon: String, color: Color, label: String, value: String,
        editContent: AnyView = AnyView(EmptyView())
    ) {
        self.id = id; self.icon = icon; self.color = color
        self.label = label; self.value = value
        self.editContent = editContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(color.opacity(0.16)).frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                }
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .kerning(0.3)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Pitcha.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 78)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
        .scaleEffect(isPressed ? 0.96 : 1)
        .overlay(editContent)
        .animation(.snappy(duration: 0.18), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

enum HistoryMode: String, Identifiable {
    case chrono
    case topScorer
    case results

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chrono: return "Historique des matchs"
        case .topScorer: return "Mes meilleurs matchs"
        case .results: return "Mes résultats"
        }
    }
}

struct MatchHistorySheet: View {
    let mode: HistoryMode
    @ObservedObject var viewModel: ProfilViewModel
    @EnvironmentObject var session: SessionViewModel

    @State private var resultFilter = "win"
    @State private var typeFilter: MatchTypeFilter = .all

    enum MatchTypeFilter: String, CaseIterable {
        case all = "Tous"
        case normal = "Normal"
        case ranked = "Classé"
    }

    private var records: [MatchRecord] {
        let base = viewModel.history.filter { record in
            switch typeFilter {
            case .all:    return true
            case .normal: return !record.isRankedRecord
            case .ranked: return record.isRankedRecord
            }
        }
        switch mode {
        case .chrono:
            return base
        case .topScorer:
            return base.sorted { ($0.goals, $0.date.timeIntervalSince1970) > ($1.goals, $1.date.timeIntervalSince1970) }
        case .results:
            return base.filter { $0.result == resultFilter }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Filtre Classé / Normal / Tous — toujours visible
                    HStack(spacing: 8) {
                        ForEach(MatchTypeFilter.allCases, id: \.self) { filter in
                            Button {
                                withAnimation(.snappy) { typeFilter = filter }
                            } label: {
                                Text(filter.rawValue)
                                    .font(.caption.bold())
                                    .foregroundStyle(typeFilter == filter ? .white : Pitcha.navy)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        Capsule().fill(
                                            typeFilter == filter
                                                ? AnyShapeStyle(
                                                    filter == .ranked
                                                        ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "F2C740"), Color(hex: "B8860B")], startPoint: .leading, endPoint: .trailing))
                                                        : AnyShapeStyle(Pitcha.gradient)
                                                  )
                                                : AnyShapeStyle(Color.gray.opacity(0.12))
                                        )
                                    )
                            }
                        }
                    }

                    if mode == .results {
                        HStack(spacing: 8) {
                            ForEach([
                                ("win",  "Victoires"),
                                ("draw", "Nuls"),
                                ("loss", "Défaites")
                            ], id: \.0) { tag, label in
                                Button { resultFilter = tag } label: {
                                    Text(label).font(.caption.bold())
                                        .foregroundStyle(resultFilter == tag ? .white : Pitcha.navy)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(
                                            Capsule().fill(resultFilter == tag
                                                ? (tag == "win" ? Color.green : tag == "draw" ? Pitcha.teal : Color.red)
                                                : Color.gray.opacity(0.12))
                                        )
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    if viewModel.historyLoading {
                        ProgressView().padding(.top, 60)
                    } else if records.isEmpty {
                        VStack(spacing: 14) {
                            VStack(spacing: -6) {
                                Text("AUCUN")
                                    .font(.system(size: 40, weight: .black))
                                    .foregroundStyle(Color.gray.opacity(0.25))
                                Text("MATCH")
                                    .font(.system(size: 46, weight: .black))
                                    .foregroundStyle(Pitcha.navy)
                            }
                            Rectangle()
                                .fill(Pitcha.mint)
                                .frame(width: 70, height: 4)
                                .clipShape(Capsule())
                            Text(mode == .results
                                ? "Aucun match avec ce résultat"
                                : "Commence à jouer pour voir ton historique !")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(records) { record in
                            HistoryRow(record: record, highlightGoals: mode == .topScorer)
                        }
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if let user = session.user {
                    await viewModel.loadHistory(user: user)
                }
            }
        }
    }
}

struct HistoryRow: View {
    let record: MatchRecord
    var highlightGoals = false

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE d MMM yyyy"
        return formatter.string(from: record.date).capitalized
    }

    var body: some View {
        HStack(spacing: 14) {
            // Pastille résultat
            ZStack {
                Circle()
                    .fill(record.resultColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(record.resultLabel.prefix(1))
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(record.resultColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Pitcha.navy)
                HStack(spacing: 6) {
                    Text(dateText)
                    Text("•")
                    Text(record.resultLabel)
                        .foregroundStyle(record.resultColor)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "soccerball.inverse")
                        .font(.caption2)
                    Text("\(record.goals)")
                        .font(highlightGoals ? .title3.weight(.heavy) : .subheadline.weight(.heavy))
                        .monospacedDigit()
                }
                .foregroundStyle(highlightGoals ? Pitcha.mint : Pitcha.tealDark)
                if record.isRankedRecord {
                    let plValue = record.plGainedValue
                    Text("\(plValue >= 0 ? "+" : "")\(plValue) PL")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(plValue >= 0 ? Color(hex: "B8860B") : .red)
                        .monospacedDigit()
                } else {
                    Text("+\(record.xpGainedValue) XP")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        )
    }
}


// MARK: - Sheet demandes d'amis (depuis la cloche)

struct FriendRequestsSheet: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var vm = FriendsViewModel()
    @State private var privateMatches: [Match] = []
    @State private var matchesListener: ListenerRegistration?
    @State private var matchOrganizers: [String: AppUser] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // ───── Invitations à un match ─────
                    if !session.pendingMatchInvites.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("INVITATIONS À UN MATCH")
                                .font(.caption.weight(.heavy))
                                .kerning(1.2)
                                .foregroundStyle(.secondary)
                            ForEach(session.pendingMatchInvites) { invite in
                                MatchInviteRow(invite: invite)
                            }
                        }
                    }

                    // ───── Matchs privés organisés par tes amis ─────
                    if !privateMatches.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("MATCHS PRIVÉS DE TES AMIS")
                                .font(.caption.weight(.heavy))
                                .kerning(1.2)
                                .foregroundStyle(.secondary)
                            ForEach(privateMatches) { match in
                                FriendPrivateMatchRow(
                                    match: match,
                                    organizerPseudo: matchOrganizers[match.organizerId]?.pseudo ?? match.organizerPseudo
                                )
                            }
                        }
                    }

                    // ───── Demandes d'amis ─────
                    VStack(alignment: .leading, spacing: 10) {
                        if !vm.requests.isEmpty {
                            Text("DEMANDES D'AMIS")
                                .font(.caption.weight(.heavy))
                                .kerning(1.2)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(vm.requests) { requester in
                            FriendRequestRow(requester: requester, viewModel: vm)
                        }
                    }

                    if vm.requests.isEmpty && privateMatches.isEmpty && session.pendingMatchInvites.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "bell.slash")
                                .font(.system(size: 44))
                                .foregroundStyle(.secondary)
                            Text("Rien de nouveau pour l'instant")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 60)
                    }
                }
                .padding()
            }
            .background(Pitcha.background.ignoresSafeArea())
            .presentationBackground(Pitcha.background)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await vm.loadRequests(uids: session.user?.incomingRequests ?? [])
            }
            .onChange(of: session.user?.friendRequests) { _, reqs in
                Task { await vm.loadRequests(uids: reqs ?? []) }
            }
            .onAppear {
                let friendIds = session.user?.friends ?? []
                matchesListener?.remove()
                guard !friendIds.isEmpty else { return }
                matchesListener = FirebaseService.shared.listenFriendsPrivateMatches(friendIds: friendIds) { matches in
                    Task { @MainActor in
                        privateMatches = matches
                        let missing = matches.map { $0.organizerId }.filter { matchOrganizers[$0] == nil }
                        if !missing.isEmpty, let users = try? await FirebaseService.shared.fetchUsers(uids: missing) {
                            for u in users { if let id = u.id { matchOrganizers[id] = u } }
                        }
                    }
                }
            }
            .onDisappear {
                matchesListener?.remove()
            }
        }
    }
}

// MARK: - Ligne invitation à un match (depuis la cloche)

struct MatchInviteRow: View {
    let invite: MatchInvite
    @EnvironmentObject var session: SessionViewModel
    @State private var isWorking = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Pitcha.teal.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: "sportscourt.fill")
                    .foregroundStyle(Pitcha.tealDark)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(invite.invitedByPseudo) t'invite")
                    .font(.subheadline.weight(.bold))
                Text(invite.matchTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isWorking {
                ProgressView()
            } else {
                Button {
                    respond(accept: false)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.gray.opacity(0.12)))
                }
                Button {
                    respond(accept: true)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Pitcha.gradient))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    private func respond(accept: Bool) {
        guard let myUid = session.user?.id else { return }
        isWorking = true
        Task {
            do {
                if accept {
                    try await FirebaseService.shared.acceptMatchInvite(matchId: invite.matchId, friendUid: myUid)
                } else {
                    try await FirebaseService.shared.declineMatchInvite(matchId: invite.matchId, friendUid: myUid)
                }
            } catch {
                // L'invitation reste visible si ça échoue (ex: match déjà complet) ;
                // l'utilisateur peut réessayer ou la refuser.
            }
            isWorking = false
        }
    }
}

// MARK: - Ligne match privé d'ami (depuis la cloche)

struct FriendPrivateMatchRow: View {
    let match: Match
    let organizerPseudo: String
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(match.type == .five ? Color(hex: "DC2626") : Color(hex: "059669"))
                        .frame(width: 44, height: 44)
                    Text(timeText)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Match privé de \(organizerPseudo)")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Pitcha.navy)
                    Text("\(match.location) • \(match.participants.count)/\(match.maxPlayers) joueurs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            if let matchId = match.id {
                MatchSheetView(matchId: matchId)
            }
        }
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: match.date)
    }
}
