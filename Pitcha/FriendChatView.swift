import SwiftUI
import FirebaseFirestore

/// Discussion privée 1-à-1 avec un ami (ouverte en tapant son pseudo).
struct FriendChatView: View {
    let friend: AppUser
    @EnvironmentObject var session: SessionViewModel
    @EnvironmentObject var tabBarVisibility: TabBarVisibility

    @State private var messages: [ChatMessage] = []
    @State private var messageText = ""
    @State private var listener: ListenerRegistration?

    private func sendCurrentMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let chatId, let sender = session.user else { return }
        messageText = ""
        Task {
            try? await FirebaseService.shared.sendDMMessage(chatId: chatId, sender: sender, text: text)
        }
    }

    private var chatId: String? {
        guard let myUid = session.user?.id, let friendUid = friend.id else { return nil }
        return FirebaseService.shared.dmChatId(myUid, friendUid)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Fil de messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if messages.isEmpty {
                            VStack(spacing: 10) {
                                InitialsAvatar(text: friend.pseudo, size: 64, cornerStyle: .circle)
                                Text("Dis bonjour à \(friend.pseudo) 👋")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 60)
                        }
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                isMine: message.senderId == session.user?.id
                            )
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let lastId = messages.last?.id {
                        withAnimation(.snappy) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            // Barre de saisie
            HStack(spacing: 10) {
                TextField("Message...", text: $messageText)
                    .submitLabel(.send)
                    .onSubmit { sendCurrentMessage() }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Button {
                    sendCurrentMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : Pitcha.teal)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle(friend.pseudo)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(friend.isOnline ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 9, height: 9)
                    Text(friend.isOnline ? "En ligne" : "Hors ligne")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            tabBarVisibility.isHidden = true
            guard let chatId else { return }
            listener?.remove()
            listener = FirebaseService.shared.listenDMMessages(chatId: chatId) { newMessages in
                Task { @MainActor in messages = newMessages }
            }
        }
        .onDisappear {
            tabBarVisibility.isHidden = false
            listener?.remove()
            listener = nil
        }
    }
}
