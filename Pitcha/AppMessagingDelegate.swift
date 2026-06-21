import Foundation
import FirebaseMessaging

/// Reçoit le token FCM et le renouvelle automatiquement.
final class AppMessagingDelegate: NSObject, MessagingDelegate {
    static let shared = AppMessagingDelegate()
    private override init() { super.init() }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        // Si l'utilisateur est connecté, on met à jour son token
        if let uid = (try? FirebaseService.shared.auth.currentUser?.uid) {
            FirebaseService.shared.usersRef.document(uid).updateData(["fcmToken": fcmToken])
        }
    }
}
