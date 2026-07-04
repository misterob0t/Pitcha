import Foundation
import FirebaseFirestore
import Combine

// MARK: - Modèle de configuration distante

struct AppConfig: Codable {
    /// Met toute l'app en maintenance (affiche l'écran de maintenance).
    var maintenanceMode: Bool = false
    var maintenanceMessage: String = "Pitcha est en maintenance. On revient très vite ! 🛠️"

    /// Version minimale obligatoire. Si la version de l'app est inférieure,
    /// la mise à jour est forcée et l'utilisateur ne peut pas continuer.
    var minVersion: String = "1.0.0"

    /// Version conseillée. Si inférieure, une bannière non-bloquante s'affiche.
    var suggestedVersion: String = "1.0.0"

    /// Email de support affiché dans l'écran de feedback.
    var supportEmail: String = "support@pitcha.app"
    var supportMessage: String = "Une question ou un bug ? On est là."
}

// MARK: - Service de configuration

@MainActor
final class AppConfigService: ObservableObject {
    static let shared = AppConfigService()

    @Published var config = AppConfig()
    @Published var isLoaded = false

    private var listener: ListenerRegistration?

    private init() { start() }

    func start() {
        listener?.remove()
        listener = Firestore.firestore()
            .collection("config").document("app")
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    if let data = snapshot?.data() {
                        self?.config = AppConfig(
                            maintenanceMode: data["maintenanceMode"] as? Bool ?? false,
                            maintenanceMessage: data["maintenanceMessage"] as? String ?? "Pitcha est en maintenance. On revient très vite ! 🛠️",
                            minVersion: data["minVersion"] as? String ?? "1.0.0",
                            suggestedVersion: data["suggestedVersion"] as? String ?? "1.0.0",
                            supportEmail: data["supportEmail"] as? String ?? "support@pitcha.app",
                            supportMessage: data["supportMessage"] as? String ?? "Une question ou un bug ? On est là."
                        )
                    }
                    self?.isLoaded = true
                }
            }
    }

    deinit { listener?.remove() }

    // MARK: - Comparaison de version (x.y.z)

    var needsForceUpdate: Bool {
        isVersion(currentVersion, olderThan: config.minVersion)
    }

    var shouldSuggestUpdate: Bool {
        isVersion(currentVersion, olderThan: config.suggestedVersion) && !needsForceUpdate
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

// MARK: - Comparaison sémantique de versions

private func isVersion(_ a: String, olderThan b: String) -> Bool {
    let lhsParts = a.split(separator: ".").compactMap { Int($0) }
    let rhsParts = b.split(separator: ".").compactMap { Int($0) }
    let maxLen = max(lhsParts.count, rhsParts.count)
    for i in 0..<maxLen {
        let l = i < lhsParts.count ? lhsParts[i] : 0
        let r = i < rhsParts.count ? rhsParts[i] : 0
        if l != r { return l < r }
    }
    return false
}
