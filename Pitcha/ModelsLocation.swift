import Foundation
import CoreLocation

// ============================================================================
// ⚠️ AVANT D'AJOUTER CE FICHIER : ajoute ces 2 lignes dans TON Models.swift,
// à l'intérieur du struct Match (Swift ne permet pas d'ajouter des stored
// properties via une extension) :
//
//     struct Match: Identifiable, Codable {
//         ...
//         var latitude: Double? = nil
//         var longitude: Double? = nil
//         ...
//     }
//
// Firestore/Codable gère les champs optionnels manquants sans problème :
// tous les matchs déjà créés (sans lat/lng) continueront de se décoder
// normalement, ils seront juste exclus du filtre "autour de moi" (voir
// MatchsViewModel ci-dessous, qui gère ce cas).
//
// Fais la même chose dans AppUser si tu veux sauvegarder la position/ville
// "par défaut" du profil (utile pour pré-remplir le centre de recherche
// avant même que l'utilisateur autorise le GPS) :
//
//     struct AppUser: Identifiable, Codable {
//         ...
//         var latitude: Double? = nil
//         var longitude: Double? = nil
//         var city: String? = nil   // si tu ne l'as pas déjà
//         ...
//     }
// ============================================================================

extension Match {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Distance en km entre ce match et un point donné. nil si le match
    /// n'a pas de coordonnées (ancien match créé avant cette fonctionnalité).
    func distanceKm(from center: CLLocationCoordinate2D) -> Double? {
        guard let coordinate else { return nil }
        let a = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let b = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return a.distance(from: b) / 1000
    }
}

extension AppUser {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
