import SwiftUI
import FirebaseFirestore

struct FriendChatView: View {
    let friend: AppUser
    @EnvironmentObject var session: SessionViewModel
    @EnvironmentObject var tabBarVisibility: TabBarVisibility
    @EnvironmentObject var network: NetworkMonitor

    @State private var messages: [ChatMessage] = []
    @State private var messageText = ""
    @FocusState private var isMessageFieldFocused: Bool
    @State private var listener: ListenerRegistration?
    @State private var showFriendProfile = false
    @State private var isPinned: Bool = false
    @State private var isMuted: Bool = false

    private var chatId: String? {
        guard let myUid = session.user?.id, let friendUid = friend.id else { return nil }
        return FirebaseService.shared.dmChatId(myUid, friendUid)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !network.isConnected { OfflineChatBanner() }
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if messages.isEmpty {
                            VStack(spacing: 10) {
                                InitialsAvatar(text: friend.pseudo, size: 64, cornerStyle: .circle)
                                Text("Dis bonjour à \(friend.pseudo) 👋")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.top, 60)
                        }
                        ForEach(messages) { message in
                            MessageBubble(message: message, isMine: message.senderId == session.user?.id, context: "dm", contextId: chatId)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let lastId = messages.last?.id {
                        withAnimation(.snappy) { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
            }

            // Saisie — le clavier reste ouvert après l'envoi ; glisser cette
            // barre vers le bas le referme (au lieu du bouton envoyer).
            HStack(spacing: 10) {
                TextField("Message...", text: $messageText)
                    .focused($isMessageFieldFocused)
                    .submitLabel(.send)
                    .onSubmit { sendCurrentMessage() }
                    .disabled(!network.isConnected)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                if messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    PhotoPickerButton { data in
                        guard let chatId, let sender = session.user else { return }
                        Task { try? await FirebaseService.shared.sendPhotoDMMessage(chatId: chatId, sender: sender, photoData: data) }
                    }
                    .disabled(!network.isConnected)
                    VoiceRecordButton { fileURL, duration in
                        guard let chatId, let sender = session.user else { return }
                        Task { try? await FirebaseService.shared.sendVoiceDMMessage(chatId: chatId, sender: sender, fileURL: fileURL, duration: duration) }
                    }
                    .disabled(!network.isConnected)
                } else {
                    Button { sendCurrentMessage() } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                            .foregroundStyle(!network.isConnected ? .gray : Pitcha.teal)
                    }
                    .disabled(!network.isConnected)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
            .gesture(
                DragGesture(minimumDistance: 15)
                    .onEnded { value in
                        if value.translation.height > 15 {
                            isMessageFieldFocused = false
                        }
                    }
            )
        }
        // Titre = bouton vers le profil de l'ami
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showFriendProfile = true } label: {
                    HStack(spacing: 6) {
                        // Indicateur en ligne
                        Circle()
                            .fill(friend.isOnline ? Color.green : Color.gray.opacity(0.5))
                            .frame(width: 8, height: 8)
                        Text(friend.pseudo)
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(Pitcha.navy)
                        Image(systemName: "chevron.down")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }

        }
        .sheet(isPresented: $showFriendProfile) {
            FriendProfileSheet(friend: friend, isPinned: $isPinned, isMuted: $isMuted, onTogglePin: {
                Task { await togglePin() }
            }, onToggleMute: {
                Task { await toggleMute() }
            })
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            tabBarVisibility.isHidden = true
            loadPreferences()
            guard let chatId else { return }
            listener?.remove()
            listener = FirebaseService.shared.listenDMMessages(chatId: chatId) { msgs in
                Task { @MainActor in messages = msgs }
            }
            if let uid = session.user?.id {
                Task {
                    await FirebaseService.shared.markDMRead(chatId: chatId, uid: uid)
                    await session.refreshUnreadCount(uid: uid)
                }
            }
        }
        .onDisappear {
            tabBarVisibility.isHidden = false
            listener?.remove()
            listener = nil
        }
    }

    private func sendCurrentMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let chatId, let sender = session.user else { return }
        messageText = ""
        Task { try? await FirebaseService.shared.sendDMMessage(chatId: chatId, sender: sender, text: text) }
        // Le clavier doit rester ouvert après l'envoi — seul un glissement
        // de la barre de saisie vers le bas doit le fermer.
        isMessageFieldFocused = true
    }

    private func loadPreferences() {
        guard let myUser = session.user, let friendUid = friend.id else { return }
        isPinned = myUser.pinnedFriends?.contains(friendUid) ?? false
        isMuted  = myUser.mutedFriends?.contains(friendUid) ?? false
    }

    private func togglePin() async {
        guard let myUid = session.user?.id, let friendUid = friend.id else { return }
        let newVal = !isPinned
        isPinned = newVal
        try? await FirebaseService.shared.pinFriend(myUid: myUid, friendUid: friendUid, pin: newVal)
    }

    private func toggleMute() async {
        guard let myUid = session.user?.id, let friendUid = friend.id else { return }
        let newVal = !isMuted
        isMuted = newVal
        try? await FirebaseService.shared.muteFriend(myUid: myUid, friendUid: friendUid, mute: newVal)
    }
}

// MARK: - Fiche profil de l'ami (tap sur le prénom)

struct FriendProfileSheet: View {
    let friend: AppUser
    @Binding var isPinned: Bool
    @Binding var isMuted: Bool
    let onTogglePin: () -> Void
    let onToggleMute: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showReportBlock = false

    var body: some View {
        VStack(spacing: 0) {
            // Profil
            VStack(spacing: 12) {
                AvatarImage(user: friend, size: 80)

                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        if isPinned {
                            Image(systemName: "star.fill")
                                .font(.caption).foregroundStyle(.yellow)
                        }
                        Text(friend.pseudo)
                            .font(.title3.weight(.heavy)).foregroundStyle(Pitcha.navy)
                    }
                    if let title = friend.title, !title.isEmpty {
                        Text(title.uppercased())
                            .font(.caption.weight(.semibold)).kerning(1.5)
                            .foregroundStyle(LinearGradient(
                                colors: [Color(hex: "FFD700"), Color(hex: "D4AF37")],
                                startPoint: .leading, endPoint: .trailing))
                    }
                    HStack(spacing: 6) {
                        Circle()
                            .fill(friend.isOnline ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                        Text(friend.isOnline ? "En ligne" : "Hors ligne")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                // Statut Classé
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(friend.rankedDivisionEnum != nil ? Color(hex: "B8860B") : .secondary)
                    Text(friend.rankedDivisionEnum?.displayName ?? "Non classé")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Pitcha.navy)
                    if friend.rankedDivisionEnum != nil {
                        Text("· \(friend.rankedPLValue) PL")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            // Actions
            VStack(spacing: 0) {
                FriendActionRow(
                    icon: isPinned ? "star.slash.fill" : "star.fill",
                    label: isPinned ? "Retirer des meilleurs amis" : "Épingler en meilleur ami",
                    tint: .yellow,
                    action: {
                        onTogglePin()
                        dismiss()
                    }
                )
                Divider().padding(.leading, 56)
                FriendActionRow(
                    icon: isMuted ? "bell.fill" : "bell.slash.fill",
                    label: isMuted ? "Réactiver les notifications" : "Désactiver les notifications",
                    tint: Pitcha.tealDark,
                    action: {
                        onToggleMute()
                        dismiss()
                    }
                )
                Divider().padding(.leading, 56)
                FriendActionRow(
                    icon: "flag.fill",
                    label: "Signaler ou bloquer",
                    tint: .red,
                    action: {
                        showReportBlock = true
                    }
                )
            }
            .sheet(isPresented: $showReportBlock) {
                if let uid = friend.id {
                    ReportBlockSheet(targetUid: uid, targetPseudo: friend.pseudo, context: "dm", contextId: nil)
                }
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
            .padding(.horizontal)
            .padding(.top, 16)

            Spacer()
        }
        .background(Pitcha.background)
    }
}

struct FriendActionRow: View {
    let icon: String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(tint)
                    .frame(width: 28)
                Text(label)
                    .font(.subheadline.bold())
                    .foregroundStyle(Pitcha.navy)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}
