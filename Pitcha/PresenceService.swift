import Foundation
import FirebaseDatabase
import FirebaseAuth

// MARK: - Présence via Realtime Database
//
// ⚠️ Pourquoi ce changement : l'ancien système écrivait dans Firestore
// toutes les 240s via une boucle côté client (Task.sleep), peu importe si
// le statut avait réellement changé. Ça facture une écriture Firestore par
// utilisateur actif toutes les 4 minutes, en continu, 24h/24.
//
// Realtime Database a un mécanisme natif côté SERVEUR : onDisconnectSetValue.
// Le client écrit son statut UNE fois à la connexion, set l'action à
// déclencher automatiquement par les serveurs Firebase à la déconnexion
// (fermeture d'app, perte réseau, crash...), puis n'a plus rien à faire.
// Zéro polling, zéro boucle, écriture uniquement quand l'état change pour
// de vrai. C'est l'architecture officiellement recommandée par Firebase
// pour la présence (RTDB + Cloud Function miroir vers Firestore).
final class PresenceService {
    static let shared = PresenceService()
    private init() {}

    private var connectedRef: DatabaseReference?
    private var statusRef: DatabaseReference?
    private var handle: DatabaseHandle?

    /// À appeler une fois à la connexion de l'utilisateur.
    func start(uid: String) {
        stop()

        let db = Database.database()
        let myStatusRef = db.reference(withPath: "status/\(uid)")
        let connectedInfoRef = db.reference(withPath: ".info/connected")
        statusRef = myStatusRef

        handle = connectedInfoRef.observe(.value) { snapshot in
            guard let isConnected = snapshot.value as? Bool, isConnected else { return }

            // 1) Préparer ce que les serveurs Firebase écriront automatiquement
            //    si l'app se déconnecte (crash, mise en arrière-plan tuée,
            //    coupure réseau...) — exécuté côté serveur, fiable à 100%.
            myStatusRef.onDisconnectSetValue([
                "online": false,
                "lastChanged": ServerValue.timestamp()
            ])

            // 2) Marquer comme en ligne maintenant que la connexion est confirmée.
            myStatusRef.setValue([
                "online": true,
                "lastChanged": ServerValue.timestamp()
            ])
        }
    }

    /// À appeler à la déconnexion volontaire (bouton "Se déconnecter").
    func stop() {
        if let handle {
            Database.database().reference(withPath: ".info/connected").removeObserver(withHandle: handle)
        }
        statusRef?.setValue([
            "online": false,
            "lastChanged": ServerValue.timestamp()
        ])
        statusRef?.removeAllObservers()
        statusRef = nil
        handle = nil
    }
}
