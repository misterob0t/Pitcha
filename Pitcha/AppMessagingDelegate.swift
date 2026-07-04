import Foundation
import FirebaseMessaging
import FirebaseFirestore
import FirebaseAuth

/// Reçoit le token FCM et le sauvegarde automatiquement dès qu'il est
/// généré ou renouvelé par Firebase (en plus de l'enregistrement explicite
/// fait dans PitchaApp à la connexion — double sécurité, peu coûteux).
final class AppMessagingDelegate: NSObject, MessagingDelegate {
    static let shared = AppMessagingDelegate()
    private override init() { super.init() }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            print("[FCM] Token reçu mais aucun utilisateur connecté pour l'instant : \(fcmToken)")
            return
        }
        Firestore.firestore().collection("users").document(uid).updateData([
            "fcmToken": fcmToken
        ])
    }
}
