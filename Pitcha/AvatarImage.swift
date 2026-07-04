import SwiftUI

/// Affiche la photo de profil d'un utilisateur quelle que soit sa source :
/// 1) photoURL (Firebase Storage, nouveau système, mis en cache par AsyncImage)
/// 2) photoBase64 (legacy, comptes pas encore migrés)
/// 3) initiales sur fond dégradé (fallback si aucune photo)
///
/// Centraliser cette logique ici évite de la dupliquer dans chaque écran
/// (carte joueur, chat, classement, mini-profil...).
struct AvatarImage: View {
    let user: AppUser
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let urlString = user.photoURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        initialsFallback
                    default:
                        ZStack {
                            Pitcha.gradient
                            ProgressView().tint(.white)
                        }
                    }
                }
            } else if let b64 = user.photoBase64,
                      let data = Data(base64Encoded: b64),
                      let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                initialsFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsFallback: some View {
        ZStack {
            Pitcha.gradient
            Text(user.initials)
                .font(.system(size: size * 0.36, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
