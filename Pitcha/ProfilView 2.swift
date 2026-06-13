import SwiftUI
import PhotosUI
import StoreKit

struct ProfilView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var viewModel = ProfilViewModel()
    @State private var showSkillsSheet = false
    @State private var historyMode: HistoryMode?
    @State private var showPasswordAlert = false
    @State private var showFriendRequests = false
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        Group {
            if let user = session.user {
                // Page fixe : tout tient à l'écran, pas de scroll
                VStack(spacing: 12) {
                    // Header : cloche + menu
                    HStack {
                        ZStack(alignment: .topTrailing) {
                            CircleIconButton(icon: "bell") { showFriendRequests = true }
                            if !(session.user?.incomingRequests.isEmpty ?? true) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 10, height: 10)
                                    .offset(x: 2, y: -2)
                            }
                        }
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
                            Button(role: .destructive) {
                                session.signOut()
                            } label: {
                                Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: {
                            CircleIconLabel(icon: "line.3.horizontal")
                        }
                    }
                    .padding(.horizontal)

                    // Bandeau niveau — TAP = distribution des points
                    LevelBanner(user: user)
                        .padding(.horizontal)
                        .onTapGesture { showSkillsSheet = true }

                    Spacer(minLength: 0)

                    // Carte FIFA (largeur carte, pas pleine largeur)
                    FlippablePlayerCard(user: user, viewModel: viewModel)
                        .frame(maxWidth: 300)

                    Spacer(minLength: 0)

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

                    #if DEBUG
                    Button {
                        Task { await viewModel.debugSimulateMatch(user: user) }
                    } label: {
                        Label("DEBUG : match joué", systemImage: "hammer.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .tint(Pitcha.teal)
                    #endif
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(PitchaBackground())
        .sheet(isPresented: $showSkillsSheet) {
            SkillsSheet(viewModel: viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NIVEAU \(user.level)")
                        .font(.title3.weight(.heavy))
                    Text(user.levelTitle)
                        .font(.caption)
                        .opacity(0.8)
                }
                Spacer()
                // Badge points dispo
                if user.skillPoints > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption)
                        Text("\(user.skillPoints) pts")
                            .font(.subheadline.weight(.heavy))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(.white.opacity(0.25)))
                }
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
                Text("+\(XPSystem.skillPointsPerLevel) points au prochain niveau")
                    .font(.caption2.bold())
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
    @State private var degree = 0.0

    var body: some View {
        ZStack {
            FifaCardFront(user: user, viewModel: viewModel)
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(.degrees(degree), axis: (x: 0, y: 1, z: 0))

            FifaCardBack(user: user, viewModel: viewModel)
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(degree + 180), axis: (x: 0, y: 1, z: 0))
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                degree += 180
                isFlipped.toggle()
            }
        }
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

// MARK: - Recto (carte FIFA, design fourni)
// Body découpé en sous-vues pour éviter le timeout du type-checker.

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
            statsRow
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

    // MARK: En-tête : poste + note générale

    private var headerRow: some View {
        HStack {
            Menu {
                ForEach(PlayerPosition.allCases) { position in
                    Button {
                        Task { await viewModel.updatePosition(position, user: user) }
                    } label: {
                        Label(position.label, systemImage: user.position == position ? "checkmark" : "")
                    }
                }
            } label: {
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
            }

            Spacer()

            ratingCircle
        }
        .padding()
    }

    private var ratingCircle: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.yellow.opacity(0.8),
                            Color.orange.opacity(0.9),
                            Color.red.opacity(0.7)
                        ]),
                        center: .center,
                        startRadius: 5,
                        endRadius: 25
                    )
                )
                .frame(width: 50, height: 50)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(color: Color.yellow.opacity(0.5), radius: 8)

            Text("\(user.overall)")
                .font(.system(size: 20, weight: .black))
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.7), radius: 2)
                .contentTransition(.numericText())
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
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
    }

    @ViewBuilder
    private var photoContent: some View {
        if let base64 = user.photoBase64,
           let data = Data(base64Encoded: base64),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Circle().fill(Color.black.opacity(0.25))
                Text(user.initials)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 16) {
            ForEach(user.displayAttributes.all, id: \.key) { attr in
                VStack(spacing: 4) {
                    Text(attr.key)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.white.opacity(0.85))
                    Text("\(attr.value)")
                        .font(.system(size: 17, weight: .black))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.6), radius: 2)
                        .contentTransition(.numericText())
                }
            }
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

// MARK: - Verso (infos personnelles éditables)

struct FifaCardBack: View {
    let user: AppUser
    @ObservedObject var viewModel: ProfilViewModel

    static let goldBorder = LinearGradient(
        gradient: Gradient(stops: [
            .init(color: Color(hex: "D4AF37").opacity(0.9), location: 0.0),
            .init(color: Color(hex: "FFD700"), location: 0.5),
            .init(color: Color(hex: "D4AF37"), location: 1.0)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    @State private var heightText = ""
    @State private var weightText = ""
    @State private var favoriteTeam = ""
    @State private var strongFoot: StrongFoot = .droit

    private var cardGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.36, blue: 0.22),
                Color(red: 0.05, green: 0.22, blue: 0.15)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("INFOS JOUEUR")
                .font(.subheadline.weight(.heavy))
                .kerning(2)
                .foregroundStyle(.white.opacity(0.85))

            VStack(spacing: 12) {
                BackInfoRow(icon: "ruler", label: "Taille") {
                    HStack(spacing: 4) {
                        TextField("—", text: $heightText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                        Text("cm")
                    }
                }
                BackInfoRow(icon: "scalemass", label: "Poids") {
                    HStack(spacing: 4) {
                        TextField("—", text: $weightText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                        Text("kg")
                    }
                }
                BackInfoRow(icon: "heart.fill", label: "Équipe favorite") {
                    TextField("—", text: $favoriteTeam)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
                BackInfoRow(icon: "shoe.2.fill", label: "Pied fort") {
                    Picker("", selection: $strongFoot) {
                        ForEach(StrongFoot.allCases) { foot in
                            Text(foot.rawValue).tag(foot)
                        }
                    }
                    .tint(.white)
                }
            }

            Button {
                Task {
                    await viewModel.savePersonalInfo(
                        user: user,
                        heightCm: Int(heightText),
                        weightKg: Int(weightText),
                        favoriteTeam: favoriteTeam,
                        strongFoot: strongFoot
                    )
                }
            } label: {
                Group {
                    if viewModel.isWorking {
                        ProgressView().tint(Pitcha.navy)
                    } else {
                        Text("Enregistrer").font(.subheadline.weight(.heavy))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Capsule().fill(Pitcha.goldGradient))
                .foregroundStyle(.white)
            }

            Text("Touche la carte pour la retourner")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .foregroundStyle(.white)
        .padding(22)
        .background(cardGradient)
        .clipShape(FIFACardShape())
        .overlay(
            FIFACardShape()
                .stroke(FifaCardBack.goldBorder, lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 10)
        .onAppear {
            heightText = user.heightCm.map(String.init) ?? ""
            weightText = user.weightKg.map(String.init) ?? ""
            favoriteTeam = user.favoriteTeam ?? ""
            strongFoot = user.strongFoot ?? .droit
        }
    }
}

struct BackInfoRow<Content: View>: View {
    let icon: String
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline.bold())
            Spacer()
            content
                .font(.subheadline.bold())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.12)))
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

// MARK: - Sheet distribution des points (sous-attributs groupés)

struct SkillsSheet: View {
    @ObservedObject var viewModel: ProfilViewModel
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                if let user = session.user {
                    VStack(spacing: 16) {
                        // En-tête points dispo
                        HStack {
                            Text("Points disponibles")
                                .font(.headline)
                            Spacer()
                            Text("\(viewModel.remainingPoints(user: user))")
                                .font(.title3.weight(.heavy))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .foregroundStyle(viewModel.remainingPoints(user: user) > 0 ? Pitcha.teal : .secondary)
                        }
                        .padding(16)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18))

                        // Groupes de sous-attributs
                        ForEach(SubAttributes.groups, id: \.main) { group in
                            SubAttributeGroup(
                                mainKey: group.main,
                                subs: group.subs,
                                user: user,
                                viewModel: viewModel
                            )
                        }

                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding()
                    .padding(.bottom, viewModel.hasPendingChanges ? 80 : 0)
                }
            }
            .navigationTitle("Ma progression")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let user = session.user, viewModel.hasPendingChanges {
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.snappy) { viewModel.resetDraft() }
                        } label: {
                            Text("Annuler")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .foregroundStyle(.primary)

                        Button {
                            Task { await viewModel.save(user: user) }
                        } label: {
                            Group {
                                if viewModel.isWorking {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Valider (\(viewModel.totalSpent()) pts)")
                                        .font(.subheadline.bold())
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Pitcha.gradient))
                            .foregroundStyle(.white)
                        }
                        .disabled(viewModel.isWorking)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
        }
    }
}

// MARK: - Groupe de sous-attributs dépliable

struct SubAttributeGroup: View {
    let mainKey: String
    let subs: [(key: String, label: String)]
    let user: AppUser
    @ObservedObject var viewModel: ProfilViewModel

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // En-tête : stat principale + moyenne live
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(mainKey)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Pitcha.navy)
                    Spacer()
                    Text("\(viewModel.draftMainValue(for: mainKey, user: user))")
                        .font(.headline.weight(.heavy))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Pitcha.teal)
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(16)
            }

            if isExpanded {
                VStack(spacing: 10) {
                    ForEach(subs, id: \.key) { sub in
                        HStack {
                            Text(sub.label)
                                .font(.subheadline)
                            Spacer()
                            Text("\(viewModel.draftValue(forSub: sub.key, user: user))")
                                .font(.subheadline.bold())
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .frame(width: 32)

                            Button {
                                withAnimation(.snappy) { viewModel.removePoint(fromSub: sub.key) }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle((viewModel.spent[sub.key] ?? 0) > 0 ? .orange : .gray.opacity(0.3))
                            }
                            .disabled((viewModel.spent[sub.key] ?? 0) == 0)

                            Button {
                                withAnimation(.snappy) { viewModel.addPoint(toSub: sub.key, user: user) }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(canAdd(sub.key) ? Pitcha.teal : .gray.opacity(0.3))
                            }
                            .disabled(!canAdd(sub.key))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .transition(.opacity)
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func canAdd(_ key: String) -> Bool {
        viewModel.remainingPoints(user: user) > 0 && viewModel.draftValue(forSub: key, user: user) < 99
    }
}



// MARK: - Historique des matchs (3 modes selon la stat tapée)

enum HistoryMode: String, Identifiable {
    case chrono       // terrain : anciens matchs, du plus récent au plus ancien
    case topScorer    // ballon : triés par buts marqués décroissants
    case results      // ratio : filtrés par victoire / nul / défaite

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

    private var records: [MatchRecord] {
        switch mode {
        case .chrono:
            return viewModel.history
        case .topScorer:
            return viewModel.history.sorted { ($0.goals, $0.date.timeIntervalSince1970) > ($1.goals, $1.date.timeIntervalSince1970) }
        case .results:
            return viewModel.history.filter { $0.result == resultFilter }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if mode == .results {
                        Picker("Résultat", selection: $resultFilter) {
                            Text("Victoires (\(session.user?.totalWins ?? 0))").tag("win")
                            Text("Nuls (\(session.user?.totalDraws ?? 0))").tag("draw")
                            Text("Défaites (\(session.user?.totalLosses ?? 0))").tag("loss")
                        }
                        .pickerStyle(.segmented)
                    }

                    if viewModel.historyLoading {
                        ProgressView().padding(.top, 60)
                    } else if records.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "sportscourt")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("Aucun match ici pour l'instant")
                                .font(.headline)
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
            .navigationTitle(mode.title)
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
                Text("+\(record.xpGained) XP")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if vm.requests.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "bell.slash")
                                .font(.system(size: 44))
                                .foregroundStyle(.secondary)
                            Text("Aucune demande en attente")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(vm.requests) { requester in
                            FriendRequestRow(requester: requester, viewModel: vm)
                        }
                    }
                }
                .padding()
            }
            .background(Pitcha.background)
            .navigationTitle("Demandes d'amis")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await vm.loadRequests(uids: session.user?.incomingRequests ?? [])
            }
            .onChange(of: session.user?.friendRequests) { _, reqs in
                Task { await vm.loadRequests(uids: reqs ?? []) }
            }
        }
    }
}
