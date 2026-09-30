import SwiftUI

/// Organisation d'un match depuis l'équipe : 4 étapes
/// (type, date, joueurs 6-22, lieu avec géocodage CLGeocoder).
struct TeamMatchOrganizerView: View {
    let team: Team
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var goingForward = true
    private let stepCount = 4

    @State private var selectedType: MatchType = .five
    @State private var date = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
    @State private var maxPlayers = 10
    @State private var address = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    private var stepHeight: CGFloat {
        switch step {
        case 0: return 400
        case 1: return 640
        case 2: return 560   // compteur joueurs : même hauteur que dans Matchs
        default: return 420
        }
    }

    private var stepTitle: String {
        switch step {
        case 0: return "Type de match"
        case 1: return "Date et heure"
        case 2: return "Nombre de joueurs"
        default: return "Lieu du match"
        }
    }

    private var canGoNext: Bool {
        switch step {
        case 1: return date > Date()
        case 3: return address.trimmingCharacters(in: .whitespaces).count >= 3
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
            // Header
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
            }
            .padding(.horizontal, 22)
            .padding(.top, 32)

            // Contenu
            ZStack {
                Group {
                    switch step {
                    case 0:
                        TypeStep(selectedType: $selectedType, maxPlayers: $maxPlayers)
                    case 1:
                        DateStep(date: $date)
                    case 2:
                        TeamPlayersStep(maxPlayers: $maxPlayers, type: selectedType)
                    default:
                        TeamLocationStep(address: $address)
                    }
                }
                .transition(slideTransition)
                .id(step)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)

            if let error = errorMessage {
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
                        Task { await createTeamMatch() }
                    }
                } label: {
                    Group {
                        if isWorking {
                            ProgressView().tint(.white)
                        } else if step < stepCount - 1 {
                            Text("Continuer").fontWeight(.bold)
                        } else {
                            Text("Organiser le match").fontWeight(.bold)
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
                .disabled(!canGoNext || isWorking)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
        .background(Pitcha.background)
        .presentationDetents([.height(stepHeight)])
        .presentationDragIndicator(.visible)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: stepHeight)
    }

    private func createTeamMatch() async {
        guard let user = session.user, let uid = user.id, let teamId = team.id else { return }
        let location = address.trimmingCharacters(in: .whitespaces)
        isWorking = true
        errorMessage = nil

        let match = Match(
            organizerId: uid,
            organizerPseudo: user.pseudo,
            type: selectedType,
            location: location,
            date: date,
            maxPlayers: maxPlayers,
            participants: [uid],
            status: .open,
            teamId: teamId,
            isPrivate: true,
            zone: nil,
            createdAt: Date(),
            unavailable: []
        )

        do {
            try await FirebaseService.shared.createTeamMatch(match, teamId: teamId, organizerPseudo: user.pseudo)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}

// MARK: - Étape joueurs (6 à 22, spécifique équipe)

struct TeamPlayersStep: View {
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

            Text("Entre 8 et \(type.maxPlayers) joueurs pour un \(type.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(22)
        .onAppear {
            // Le max dépend du type (5v5 = 10, 11v11 = 22) — jamais un
            // plafond générique à 22 quel que soit le format choisi.
            maxPlayers = min(max(maxPlayers, 8), type.maxPlayers)
        }
        .onChange(of: type) { _, newType in
            // Si l'utilisateur revient en arrière et change de type après
            // avoir déjà réglé son nombre de joueurs, on recadre aussitôt.
            maxPlayers = min(max(maxPlayers, 8), newType.maxPlayers)
        }
    }
}

// MARK: - Étape lieu (champ simple, sans recherche)

struct TeamLocationStep: View {
    @Binding var address: String

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Terrain / Adresse du match")
                    .font(.headline)
                    .foregroundStyle(Pitcha.navy)
                PitchaTextField(icon: "mappin.and.ellipse", placeholder: "Ex : City Stade de Meaux", text: $address)
            }

            Spacer()
        }
        .padding(22)
    }
}
