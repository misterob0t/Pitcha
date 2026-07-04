import SwiftUI

struct CreateMatchView: View {
    @ObservedObject var viewModel: MatchsViewModel
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    // Étapes
    @State private var step = 0
    @State private var goingForward = true
    private let stepCount = 5

    // Données du match
    @State private var selectedType: MatchType = .five
    @State private var isPrivate = false
    @State private var date = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
    @State private var maxPlayers = MatchType.five.maxPlayers
    @State private var zone = ""
    @State private var address = ""

    /// Hauteur de la sheet ajustée au contenu de chaque étape.
    private var stepHeight: CGFloat {
        switch step {
        case 0: return 420   // type (2 cartes)
        case 1: return 420   // visibilité
        case 2: return 660   // calendrier
        case 3: return 560   // compteur joueurs
        default: return 460  // lieu
        }
    }

    private var stepTitle: String {
        switch step {
        case 0: return "Type de match"
        case 1: return "Visibilité"
        case 2: return "Date et heure"
        case 3: return "Nombre de joueurs"
        default: return "Lieu"
        }
    }

    private var canGoNext: Bool {
        switch step {
        case 2: return date > Date()
        case 4: return !zone.isEmpty
                    && address.trimmingCharacters(in: .whitespaces).count >= 3
        default: return true
        }
    }

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header : progression
            VStack(spacing: 14) {
                HStack {
                    Button("Fermer") { dismiss() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Étape \(step + 1)/\(stepCount)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                // Barre de progression animée
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.07))
                        Capsule()
                            .fill(Pitcha.gradient)
                            .frame(width: geo.size.width * CGFloat(step + 1) / CGFloat(stepCount))
                            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
                    }
                }
                .frame(height: 8)

                Text(stepTitle)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Pitcha.navy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)
                    .animation(.snappy, value: step)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)

            // Contenu de l'étape (transitions asymétriques)
            ZStack {
                Group {
                    switch step {
                    case 0:
                        TypeStep(selectedType: $selectedType, maxPlayers: $maxPlayers)
                    case 1:
                        VisibilityStep(isPrivate: $isPrivate)
                    case 2:
                        DateStep(date: $date)
                    case 3:
                        PlayersStep(maxPlayers: $maxPlayers, type: selectedType)
                    default:
                        LocationStep(zone: $zone, address: $address)
                    }
                }
                .transition(slideTransition)
                .id(step)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 6)
            }

            // Navigation
            HStack(spacing: 12) {
                if step > 0 {
                    Button {
                        goingForward = false
                        withAnimation { step -= 1 }
                    } label: {
                        Image(systemName: "arrow.left")
                            .fontWeight(.bold)
                            .foregroundStyle(Pitcha.navy)
                            .frame(width: 54, height: 54)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.06)))
                    }
                }

                Button {
                    if step < stepCount - 1 {
                        goingForward = true
                        withAnimation { step += 1 }
                    } else {
                        Task {
                            guard let user = session.user else { return }
                            let success = await viewModel.create(
                                type: selectedType,
                                isPrivate: isPrivate,
                                date: date,
                                maxPlayers: maxPlayers,
                                zone: zone,
                                address: address,
                                organizer: user
                            )
                            if success { dismiss() }
                        }
                    }
                } label: {
                    Group {
                        if viewModel.isWorking {
                            ProgressView().tint(.white)
                        } else if step < stepCount - 1 {
                            Text("Continuer").fontWeight(.bold)
                        } else {
                            Text("Créer le match \(selectedType.displayName) • 1 🪙").fontWeight(.bold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(canGoNext ? AnyShapeStyle(Pitcha.gradient) : AnyShapeStyle(Color.gray.opacity(0.4)))
                    )
                    .foregroundStyle(.white)
                }
                .disabled(!canGoNext || viewModel.isWorking)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
        .background(Pitcha.background)
        .presentationDetents([.height(stepHeight)])
        .presentationDragIndicator(.visible)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: stepHeight)
        .onAppear {
            viewModel.errorMessage = nil
            if zone.isEmpty { zone = viewModel.city }
        }
    }
}

// MARK: - Étape 1 : Type

struct TypeStep: View {
    @Binding var selectedType: MatchType
    @Binding var maxPlayers: Int

    /// Seuls deux formats à la création : Five (5v5) ou Foot (classique).
    static let offeredTypes: [MatchType] = [.five, .eleven]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(Self.offeredTypes) { type in
                Button {
                    withAnimation(.snappy) {
                        selectedType = type
                        maxPlayers = type.maxPlayers
                    }
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "soccerball.inverse")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.displayName)
                                .font(.title3.weight(.heavy))
                            Text(type.subtitle)
                                .font(.caption)
                                .opacity(0.8)
                        }
                        Spacer()
                        Text("\(type.maxPlayers) joueurs")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.white.opacity(selectedType == type ? 0.25 : 0.0)))
                        Image(systemName: selectedType == type ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                    }
                    .foregroundStyle(selectedType == type ? .white : Pitcha.navy)
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(selectedType == type ? AnyShapeStyle(Pitcha.gradient) : AnyShapeStyle(Color.white))
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                    )
                }
            }
            Spacer()
        }
        .padding(22)
    }
}

// MARK: - Étape 2 : Visibilité

struct VisibilityStep: View {
    @Binding var isPrivate: Bool

    var body: some View {
        VStack(spacing: 14) {
            VisibilityCard(
                title: "Public",
                subtitle: "Tout le monde peut rejoindre",
                icon: "globe",
                isSelected: !isPrivate
            ) { isPrivate = false }

            VisibilityCard(
                title: "Privé",
                subtitle: "Sur invitation uniquement",
                icon: "lock.fill",
                isSelected: isPrivate
            ) { isPrivate = true }

            Spacer()
        }
        .padding(22)
    }
}

struct VisibilityCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title3.weight(.heavy))
                    Text(subtitle)
                        .font(.caption)
                        .opacity(0.8)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
            }
            .foregroundStyle(isSelected ? .white : Pitcha.navy)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? AnyShapeStyle(Pitcha.gradient) : AnyShapeStyle(Color.white))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
            )
        }
    }
}

// MARK: - Étape 3 : Date

struct DateStep: View {
    @Binding var date: Date

    var body: some View {
        VStack(spacing: 16) {
            DatePicker(
                "Date du match",
                selection: $date,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .tint(Pitcha.teal)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
            )
            Spacer()
        }
        .padding(22)
    }
}

// MARK: - Étape 4 : Nombre de joueurs

struct PlayersStep: View {
    @Binding var maxPlayers: Int
    let type: MatchType

    var body: some View {
        VStack(spacing: 26) {

            Text("\(maxPlayers)")
                .font(.system(size: 90, weight: .black, design: .rounded))
                .foregroundStyle(Pitcha.tealDark)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("joueurs maximum")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 28) {
                CounterButton(icon: "minus", enabled: maxPlayers > 8) {
                    withAnimation(.snappy) { maxPlayers -= 1 }
                }
                CounterButton(icon: "plus", enabled: maxPlayers < type.maxPlayers) {
                    withAnimation(.snappy) { maxPlayers += 1 }
                }
            }

            Text("Entre 8 et \(type.maxPlayers) pour un \(type.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)

        }
        .padding(22)
    }
}

struct CounterButton: View {
    let icon: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title.bold())
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(
                    Circle().fill(enabled ? AnyShapeStyle(Pitcha.gradient) : AnyShapeStyle(Color.gray.opacity(0.35)))
                )
                .shadow(color: enabled ? Pitcha.teal.opacity(0.35) : .clear, radius: 8, y: 4)
        }
        .disabled(!enabled)
    }
}

// MARK: - Étape 5 : Lieu (zone = villes du filtre)

struct LocationStep: View {
    @Binding var zone: String
    @Binding var address: String

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Zone géographique")
                    .font(.headline)
                    .foregroundStyle(Pitcha.navy)
                // Les mêmes villes que le filtre de l'écran Matchs :
                // le match créé apparaîtra directement dans ce filtre.
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(MatchsViewModel.cities, id: \.self) { city in
                        Button {
                            withAnimation(.snappy) { zone = city }
                        } label: {
                            Text(city)
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule().fill(zone == city
                                                   ? AnyShapeStyle(Pitcha.gradient)
                                                   : AnyShapeStyle(Color.white))
                                )
                                .foregroundStyle(zone == city ? .white : Pitcha.navy)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Adresse précise")
                    .font(.headline)
                    .foregroundStyle(Pitcha.navy)
                PitchaTextField(icon: "mappin.and.ellipse", placeholder: "Ex : City Stade, 12 rue du Parc", text: $address)
            }

            Spacer()
        }
        .padding(22)
    }
}
