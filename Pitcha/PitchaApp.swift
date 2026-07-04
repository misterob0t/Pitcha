import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        BackgroundTaskService.shared.registerTasks()
        UNUserNotificationCenter.current().delegate = NotificationService.shared
        Messaging.messaging().delegate = AppMessagingDelegate.shared
        return true
    }
}

@main
struct PitchaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var session       = SessionViewModel()
    @StateObject private var notifications = NotificationService.shared
    @StateObject private var network       = NetworkMonitor()
    @StateObject private var appConfig     = AppConfigService.shared
    @StateObject private var storeKit      = StoreKitManager.shared
    @State private var updateBannerDismissed = false

    var body: some Scene {
        WindowGroup {
            Group {
                if !appConfig.isLoaded {
                    SplashView()
                } else if appConfig.config.maintenanceMode {
                    MaintenanceView(message: appConfig.config.maintenanceMessage)
                } else if appConfig.needsForceUpdate {
                    ForceUpdateView()
                } else {
                    ZStack(alignment: .top) {
                        ContentView()
                            .environmentObject(session)
                            .environmentObject(network)
                            .environmentObject(storeKit)
                            .tint(Pitcha.teal)

                        if appConfig.shouldSuggestUpdate && !updateBannerDismissed {
                            UpdateBanner(dismissed: $updateBannerDismissed)
                                .padding(.top, 8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.snappy, value: updateBannerDismissed)
                    .task {
                        // Notifications locales uniquement pour l'instant
                        // (push/FCM désactivé, voir NotificationService.swift)
                        await NotificationService.shared.requestPermission()
                        // StoreKit : vérifier le statut Premium au lancement
                        await StoreKitManager.shared.updatePremiumStatus()
                    }
                }
            }
            // Mode clair forcé sur toute l'app : ignore le réglage système
            // (Réglages > Luminosité et affichage > Sombre) et tout toggle
            // interne éventuel. Appliqué au niveau racine pour couvrir aussi
            // les sheets, alerts et le SplashView.
            .preferredColorScheme(.light)
        }
    }
}
