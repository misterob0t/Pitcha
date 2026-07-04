import SwiftUI
import Combine

/// Gère le thème visuel global de l'app. Persiste le choix entre les
/// sessions et notifie toute la hiérarchie de vues lors du changement
/// (injecté en @EnvironmentObject à la racine).
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var isGirlsMode: Bool {
        didSet { UserDefaults.standard.set(isGirlsMode, forKey: "pitcha.girlsMode") }
    }

    private init() {
        isGirlsMode = UserDefaults.standard.bool(forKey: "pitcha.girlsMode")
    }

    func toggle() {
        isGirlsMode.toggle()
    }
}
