import Foundation
import Combine
import FirebaseMessaging
import FirebaseFirestore
import UserNotifications
import UIKit

// MARK: - Service de notifications push

final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    @Published var permissionGranted = false

    /// Rempli quand l'utilisateur TAPE sur une notification (push ou locale)
    /// contenant un "action" reconnu — la vue qui doit réagir (ProfilView,
    /// via MainTabView) l'observe et se remet à nil une fois traité.
    @Published var deepLinkTarget: String? = nil

    private override init() { super.init() }

    // MARK: - Demande de permission (à appeler au 1er lancement)

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        print("🔔 [Notif] Statut actuel : \(settings.authorizationStatus.rawValue) (0=notDetermined, 1=denied, 2=authorized, 3=provisional, 4=ephemeral)")

        if settings.authorizationStatus == .notDetermined {
            print("🔔 [Notif] Jamais demandé -> affichage de la popup système")
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            print("🔔 [Notif] Résultat de la popup : granted=\(granted)")
            await MainActor.run { permissionGranted = granted }
            if granted {
                await MainActor.run {
                    print("🔔 [Notif] Appel de registerForRemoteNotifications()")
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        } else if settings.authorizationStatus == .authorized {
            print("🔔 [Notif] Déjà autorisé précédemment -> registerForRemoteNotifications()")
            await MainActor.run { permissionGranted = true }
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } else if settings.authorizationStatus == .denied {
            print("🔔 [Notif] ⚠️ REFUSÉ précédemment. Pour réactiver : Réglages iPhone > Pitcha > Notifications > Activer")
        }
    }

    // MARK: - Enregistrement du token FCM dans Firestore
    //
    // ⚠️ registerForRemoteNotifications() est asynchrone : le vrai token
    // APNs arrive avec un court délai (1-2s typiquement) après l'appel.
    // Si on demande le token FCM trop tôt, Firebase répond "No APNS token
    // specified" — pas une vraie erreur, juste "pas encore prêt".
    // On réessaie automatiquement quelques fois avec un court délai.

    func saveFCMToken(uid: String, retriesLeft: Int = 4) {
        print("🔔 [Notif] saveFCMToken appelé pour uid=\(uid) (tentatives restantes: \(retriesLeft))")
        Messaging.messaging().token { [weak self] token, error in
            if let error {
                let isApnsNotReady = (error as NSError).localizedDescription.contains("APNS")
                if isApnsNotReady && retriesLeft > 0 {
                    print("🔔 [Notif] ⏳ APNs pas encore prêt, nouvelle tentative dans 1.5s...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self?.saveFCMToken(uid: uid, retriesLeft: retriesLeft - 1)
                    }
                } else {
                    print("🔔 [Notif] ❌ Abandon après plusieurs tentatives : \(error.localizedDescription)")
                }
                return
            }
            guard let token else {
                print("🔔 [Notif] ❌ Token FCM nil sans erreur explicite")
                return
            }
            print("🔔 [Notif] ✅ Token FCM récupéré : \(token.prefix(20))...")

            FirebaseService.shared.usersRef.document(uid).updateData([
                "fcmToken": token
            ]) { error in
                if let error {
                    print("🔔 [Notif] ❌ Échec écriture Firestore : \(error.localizedDescription)")
                } else {
                    print("🔔 [Notif] ✅ Token écrit dans Firestore avec succès pour uid=\(uid)")
                }
            }
        }
    }

    // MARK: - Notification locale (quand l'app est au premier plan)

    static func showLocal(title: String, body: String, data: [AnyHashable: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = data
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil   // immédiat
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Delegate UNUserNotificationCenter (notifications en avant-plan)

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
        // Notifications push serveur (voir index.js) : action="friendRequest"
        // ou notifications locales (invitation à un match) : même clé.
        // On ne gère que ces deux cas pour l'instant — les autres actions
        // (dm, teamMessage, result, vote, contested) resteront pour un
        // futur chantier de deep-linking plus complet.
        if let action = response.notification.request.content.userInfo["action"] as? String,
           action == "friendRequest" || action == "matchInvite" {
            DispatchQueue.main.async {
                self.deepLinkTarget = action
            }
        }
        completionHandler()
    }
}
