import Foundation
import FirebaseStorage
import FirebaseFirestore
import UIKit

// MARK: - Photos de profil via Firebase Storage
//
// ⚠️ Pourquoi ce changement : stocker une photo en base64 dans un document
// Firestore facture la lecture de TOUTE la chaîne base64 à chaque fois que
// le document est lu (recherche d'ami, classement, carte joueur...), même
// si la photo n'est pas affichée à ce moment précis. Firebase Storage est
// fait pour ça : stockage objet bon marché, servi par CDN, et la photo
// n'est téléchargée que quand on en a réellement besoin (AsyncImage côté
// client gère même un cache automatique).

extension FirebaseService {

    private var storage: Storage { Storage.storage() }

    /// Upload la photo de profil et retourne son URL publique.
    /// Compresse en JPEG qualité 0.7, redimensionne à 400px max — suffisant
    /// pour l'affichage carte/avatar, et ça réduit encore le coût de stockage.
    func uploadProfilePhoto(uid: String, image: UIImage) async throws -> String {
        let resized = Self.resize(image, maxDimension: 400)
        guard let data = resized.jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "Pitcha", code: -1, userInfo: [NSLocalizedDescriptionKey: "Impossible de compresser l'image."])
        }

        let ref = storage.reference().child("profile_photos/\(uid).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()

        // Mettre à jour le profil : nouvelle URL, et on efface l'ancien
        // champ base64 s'il existait (migration douce au passage).
        try await usersRef.document(uid).updateData([
            "photoURL": url.absoluteString,
            "photoBase64": FieldValue.delete()
        ])

        return url.absoluteString
    }

    /// Supprime la photo de profil (Storage + référence Firestore).
    func deleteProfilePhoto(uid: String) async throws {
        let ref = storage.reference().child("profile_photos/\(uid).jpg")
        try? await ref.delete()  // pas grave si déjà absent
        try await usersRef.document(uid).updateData([
            "photoURL": FieldValue.delete()
        ])
    }

    /// Redimensionne une image pour ne pas uploader plus gros que nécessaire.
    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension else { return image }

        let scale = maxDimension / largestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
