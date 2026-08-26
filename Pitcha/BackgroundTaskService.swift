import Foundation
import BackgroundTasks
import FirebaseFirestore

// MARK: - Identifiants des tâches background

enum BGTaskID {
    /// ⚠️ OBSOLÈTE depuis la migration serveur : le timeout 48h est
    /// désormais géré de façon fiable par la Cloud Function planifiée
    /// `finalizeStaleMatches` (tourne toutes les heures, indépendamment
    /// de si l'app est ouverte/en arrière-plan sur un appareil quelconque).
    /// Gardé ici pour ne pas casser les appels existants (submitMatchResult,
    /// AppDelegate), mais ne fait plus rien d'utile — à retirer complètement
    /// au prochain nettoyage.
    static let matchTimeout = "com.pitcha.match-timeout"
}

// MARK: - Service de tâches background

final class BackgroundTaskService {
    static let shared = BackgroundTaskService()
    private init() {}

    // MARK: - Enregistrement (à appeler dans AppDelegate)

    func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BGTaskID.matchTimeout,
            using: nil
        ) { task in
            // Ne fait plus rien : voir le commentaire sur BGTaskID.matchTimeout.
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - Planification (appelée après soumission d'un score)

    /// Ne planifie plus rien — le timeout 48h est géré côté serveur.
    /// Signature conservée pour ne pas casser l'appel dans
    /// FirebaseService_MatchSheet.swift (submitMatchResult).
    func scheduleMatchTimeoutCheck(submittedAt: Date) {
        // Volontairement vide.
    }
}

