import Foundation
import BackgroundTasks
import FirebaseFirestore

// MARK: - Identifiants des tâches background

enum BGTaskID {
    /// Vérifie les matchs en pendingValidation depuis plus de 48h
    /// et distribue l'XP à 80% automatiquement.
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
            self.handleMatchTimeoutTask(task as! BGProcessingTask)
        }
    }

    // MARK: - Planification (à appeler après soumission d'un score)

    /// Planifie la tâche pour s'exécuter au plus tôt 48h après `submittedAt`.
    func scheduleMatchTimeoutCheck(submittedAt: Date) {
        let request = BGProcessingTaskRequest(identifier: BGTaskID.matchTimeout)
        // Exécuter au plus tôt 48h après la soumission
        request.earliestBeginDate = submittedAt.addingTimeInterval(48 * 3600)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BGTask] Échec de planification : \(error)")
        }
    }

    // MARK: - Exécution de la tâche

    private func handleMatchTimeoutTask(_ task: BGProcessingTask) {
        // Replanifier immédiatement pour la prochaine fois
        scheduleMatchTimeoutCheck(submittedAt: Date())

        let taskWork = Task {
            await runTimeoutCheck()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            taskWork.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Logique : distribuer les matchs expirés

    @MainActor
    private func runTimeoutCheck() async {
        let service = FirebaseService.shared
        do {
            // Récupérer tous les matchs en pendingValidation
            let snapshot = try await service.matchesRef
                .whereField("status", isEqualTo: MatchStatus.pendingValidation.rawValue)
                .getDocuments()

            let matches = snapshot.documents.compactMap { try? $0.data(as: Match.self) }
            let now = Date()

            for match in matches {
                guard let submittedAt = match.scoreSubmittedAt,
                      now.timeIntervalSince(submittedAt) > 48 * 3600 else { continue }
                // 48h écoulées sans majorité → distribuer à 80%
                try await service.checkTimeoutDistribution(match: match)
            }
        } catch {
            print("[BGTask] Erreur timeout check : \(error)")
        }
    }
}
