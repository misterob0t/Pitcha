import Foundation
import Combine
import FirebaseMessaging
import FirebaseFirestore
import UserNotifications
import UIKit

// MARK: - Service de notifications
//
// ⚠️ Push notifications (APNs/FCM) désactivées temporairement — la config
// APNs (certificats, provisioning) n'est pas encore stabilisée. En attendant,
// on utilise uniquement des notifications LOCALES (showLocal), qui ne
// nécessitent aucun serveur ni token et fonctionnent immédiatement.
// Pour réactiver le push plus tard : décommenter registerForRemoteNotifications()
// et saveFCMToken() ci-dessous, et l'appel à saveFCMToken dans PitchaApp.swift.

final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    @Published var permissionGranted = false

    private override init() { super.init() }

    // MARK: - Demande de permission (nécessaire même pour les notifs locales)

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            await MainActor.run { permissionGranted = granted }
            // Push désactivé pour l'instant : pas d'appel à registerForRemoteNotifications()
        } else if settings.authorizationStatus == .authorized {
            await MainActor.run { permissionGranted = true }
            // Push désactivé pour l'instant : pas d'appel à registerForRemoteNotifications()
        }
    }

    // MARK: - Enregistrement du token FCM — DÉSACTIVÉ temporairement
    //
    // func saveFCMToken(uid: String, retriesLeft: Int = 4) { ... }
    // Laissé de côté volontairement : on repassera dessus une fois la
    // config APNs (certificats + provisioning) stabilisée.

    // MARK: - Notification locale (fonctionne sans APNs, sans serveur)

    static func showLocal(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil   // immédiat
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Delegate UNUserNotificationCenter (notifications locales en avant-plan)

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Afficher la notification même quand l'app est ouverte
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
