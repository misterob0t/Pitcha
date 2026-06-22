import Foundation
import FirebaseFirestore

/// Un signalement envoyé par un utilisateur contre un autre.
/// Écriture uniquement depuis le client ; lecture réservée à l'admin
/// (via la console Firebase ou un futur back-office).
struct UserReport: Codable {
    var reporterId: String
    var reportedId: String
    var reportedPseudo: String
    var reason: String
    var context: String      // "match", "team", "dm", "profile"
    var contextId: String?   // matchId / teamId / chatId selon le contexte
    var createdAt: Date
}
