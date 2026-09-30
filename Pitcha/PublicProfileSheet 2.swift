import SwiftUI

/// Sheet affichant le profil public d'un membre (équipe ou club) : identité,
/// stats de jeu, et bouton "Ajouter en ami" si ce n'est pas déjà le cas.
///
/// vue est en LECTURE SEULE : pas de PhotosPicker, pas de Menu pour changer
/// le poste — ce sont les infos d'un AUTRE joueur, jamais les siennes.
///
/// Les sous-stats (VIT/TIR/PAS/DRI/DEF/PHY) et la note globale (OVR) ne sont
/// plus utilisées dans l'app — elles ont été retirées de cet écran.
struct PublicProfileSheet: View {
    let member: AppUser
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isSending = false
    @State private var localRequestSent = false
    @State private var errorMessage: String?

    private var myUid: String? { session.user?.id }
    private var isMe: Bool { member.id != nil && member.id == myUid }
    private var isFriend: Bool {
        guard let uid = member.id else { return false }
        return session.user?.friends.contains(uid) ?? false
    }
    /// Une demande est déjà en attente si son document friendRequests contient
    /// mon uid (elle a été envoyée avant, potentiellement depuis un autre écran).
    private var requestAlreadySent: Bool {
        localRequestSent || (myUid.map { member.incomingRequests.contains($0) } ?? false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    AvatarImage(user: member, size: 110)
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                        .padding(.top, 8)

                    VStack(spacing: 4) {
                        Text(member.pseudo)
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(Pitcha.navy)
                        if let title = member.title, !title.isEmpty {
                            Text(title.uppercased())
                                .font(.caption.weight(.bold))
                                .kerning(1.5)
                                .foregroundStyle(Pitcha.tealDark)
                        }
                        Text("Niv. \(member.level) · \(member.levelTitle)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Poste (l'OVR et les sous-stats ne sont plus affichés)
                    VStack(spacing: 2) {
                        Text(member.position.rawValue)
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(Pitcha.navy)
                        Text("Poste")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }

                    // Stats de jeu
                    HStack(spacing: 12) {
                        StatCard(icon: "sportscourt.fill", value: "\(member.totalMatches)")
                        StatCard(icon: "soccerball.inverse", value: "\(member.totalGoals)", accent: true)
                        StatCard(icon: "chart.bar.fill", value: "\(member.totalWins)/\(member.totalDraws)/\(member.totalLosses)")
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if !isMe {
                        Button {
                            Task { await sendRequest() }
                        } label: {
                            Group {
                                if isSending {
                                    ProgressView().tint(.white)
                                } else {
                                    Label(
                                        isFriend ? "Déjà ami" : (requestAlreadySent ? "Demande envoyée" : "Ajouter en ami"),
                                        systemImage: isFriend ? "checkmark" : "person.badge.plus"
                                    )
                                    .fontWeight(.bold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill((isFriend || requestAlreadySent)
                                          ? AnyShapeStyle(Color.gray.opacity(0.25))
                                          : AnyShapeStyle(Pitcha.gradient))
                            )
                            .foregroundStyle((isFriend || requestAlreadySent) ? Color.secondary : Color.white)
                        }
                        .disabled(isFriend || requestAlreadySent || isSending)
                    }
                }
                .padding(22)
            }
            .background(Pitcha.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func sendRequest() async {
        guard let myUid, let targetUid = member.id, myUid != targetUid else { return }
        isSending = true
        errorMessage = nil
        do {
            try await FirebaseService.shared.sendFriendRequest(myUid: myUid, to: targetUid)
            localRequestSent = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}
