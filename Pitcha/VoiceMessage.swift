import Foundation
import AVFoundation
import SwiftUI
import PhotosUI
import Combine

// MARK: - Enregistrement d'un vocal

/// Encapsule AVAudioRecorder — un seul enregistrement à la fois, format
/// compact (AAC/.m4a) pour rester léger côté Storage et transfert mobile.
@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    @Published var blinkOn = true
    @Published var permissionDenied = false

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var recordedFileURL: URL?

    /// Durée max d'un vocal — évite un fichier énorme envoyé par erreur si
    /// quelqu'un oublie de finaliser.
    static let maxDuration: TimeInterval = 120

    func requestPermissionAndStart() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                if granted {
                    self.startRecording()
                } else {
                    self.permissionDenied = true
                }
            }
        }
    }

    private func startRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder?.record()
            recordedFileURL = fileURL
            isRecording = true
            elapsed = 0
            blinkOn = true

            // .common (et pas le mode par défaut) pour que le chrono reste
            // précis même si l'interface est en train de gérer un autre
            // geste/scroll en parallèle — sinon le Timer peut être retardé
            // puis "rattraper" son retard d'un coup, donnant l'impression
            // que les secondes défilent trop vite.
            let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.elapsed += 0.5
                    self.blinkOn.toggle()
                    if self.elapsed >= Self.maxDuration { self.stop() }
                }
            }
            RunLoop.current.add(t, forMode: .common)
            timer = t
        } catch {
            isRecording = false
        }
    }

    /// Arrête et garde le fichier — appelant doit ensuite l'envoyer ou l'annuler.
    func stop() {
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
    }

    /// Arrête ET supprime le fichier — utilisé quand on annule (glissement).
    func cancel() {
        stop()
        if let url = recordedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedFileURL = nil
        elapsed = 0
    }
}

// MARK: - Lecture d'un vocal reçu

@MainActor
final class VoicePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var progress: Double = 0   // 0...1

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var currentURLString: String?

    func togglePlay(urlString: String) {
        if isPlaying && currentURLString == urlString {
            pause()
            return
        }
        guard let url = URL(string: urlString) else { return }
        currentURLString = urlString

        // Vocal déjà en cache local ? sinon télécharge d'abord.
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                self.player = player
                player.play()
                self.isPlaying = true
                self.startProgressTimer()
            } catch {
                // Échec silencieux — l'UI reste sur l'état "non lu", l'utilisateur peut retaper.
            }
        }
    }

    private func startProgressTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player, player.duration > 0 else { return }
                self.progress = player.currentTime / player.duration
            }
        }
    }

    private func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.progress = 0
            self.timer?.invalidate()
        }
    }
}

// MARK: - Bouton d'enregistrement (tap pour démarrer, 2 boutons pour finir)

struct VoiceRecordButton: View {
    /// Appelé avec le fichier temporaire une fois l'enregistrement validé.
    /// L'appelant se charge de l'upload + l'envoi.
    var onFinish: (URL, TimeInterval) -> Void

    @StateObject private var recorder = VoiceRecorder()

    var body: some View {
        if recorder.isRecording {
            HStack(spacing: 10) {
                // Annuler — supprime sans envoyer.
                Button {
                    recorder.stop()
                    recorder.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.red))
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 9, height: 9)
                        .opacity(recorder.blinkOn ? 1 : 0.3)
                    Text(formattedElapsed)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Pitcha.navy)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(.secondarySystemBackground)))

                // Envoyer — arrête et transmet à l'appelant.
                Button {
                    recorder.stop()
                    if let url = recorder.recordedFileURL, recorder.elapsed >= 1 {
                        onFinish(url, recorder.elapsed)
                    } else {
                        recorder.cancel()
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Pitcha.teal))
                }
            }
            .transition(.scale(scale: 0.85).combined(with: .opacity))
            .animation(.spring(response: 0.25), value: recorder.isRecording)
        } else {
            Button {
                recorder.requestPermissionAndStart()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Pitcha.teal))
            }
            .alert("Micro désactivé", isPresented: $recorder.permissionDenied) {
                Button("Réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Autorise l'accès au micro dans Réglages pour envoyer des messages vocaux.")
            }
        }
    }

    private var formattedElapsed: String {
        let s = Int(recorder.elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Bulle de lecture d'un vocal reçu

struct VoiceMessageBubble: View {
    let url: String
    let duration: Double
    let isMine: Bool

    @StateObject private var player = VoicePlayer()

    var body: some View {
        HStack(spacing: 10) {
            Button {
                player.togglePlay(urlString: url)
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(isMine ? Pitcha.teal : .white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(isMine ? Color.white : Pitcha.teal))
            }

            // Barre de progression simplifiée façon vocal — pas une vraie
            // forme d'onde (demanderait d'analyser l'audio), mais donne le
            // même repère visuel utile : où on en est dans la lecture.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill((isMine ? Color.white : Pitcha.teal).opacity(0.25))
                    Capsule().fill(isMine ? Color.white : Pitcha.teal)
                        .frame(width: geo.size.width * player.progress)
                }
            }
            .frame(height: 4)

            Text(formattedDuration)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isMine ? .white.opacity(0.85) : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 190)
    }

    private var formattedDuration: String {
        let s = Int(duration)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Bouton photo (choix dans la pellicule)

struct PhotoPickerButton: View {
    /// Appelé avec les données JPEG déjà compressées, prêtes à uploader.
    var onPicked: (Data) -> Void

    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Pitcha.teal))
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                guard let data = try? await newItem.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data),
                      // Compression avant envoi — une vraie photo d'iPhone
                      // ferait plusieurs Mo par message autrement, pour un
                      // gain de qualité invisible dans une bulle de chat.
                      let compressed = uiImage.jpegData(compressionQuality: 0.6) else { return }
                onPicked(compressed)
                selectedItem = nil
            }
        }
    }
}

// MARK: - Bulle photo (tap pour agrandir en plein écran)

struct PhotoMessageBubble: View {
    let url: String
    @State private var showFullscreen = false

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Color.gray.opacity(0.15).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            default:
                Color.gray.opacity(0.1).overlay(ProgressView())
            }
        }
        .frame(width: 190, height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture { showFullscreen = true }
        .fullScreenCover(isPresented: $showFullscreen) {
            ZStack {
                Color.black.ignoresSafeArea()
                AsyncImage(url: URL(string: url)) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFit()
                    }
                }
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            showFullscreen = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding()
                        }
                    }
                    Spacer()
                }
            }
        }
    }
}
