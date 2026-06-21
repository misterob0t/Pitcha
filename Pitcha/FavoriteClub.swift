import SwiftUI

// MARK: - Catalogue d'équipes (Ligue 1 + grands clubs européens)
//
// ⚠️ Les vrais blasons (PSG, OM, Real Madrid, etc.) sont des marques
// déposées : je ne peux pas les générer ni les reproduire. Ce fichier
// définit juste la liste + le nom d'asset attendu. Pour afficher le vrai
// logo, ajoute l'image dans Assets.xcassets avec EXACTEMENT le nom indiqué
// dans `assetName` (ex: "crest_psg"). Sans l'image, un cercle coloré avec
// les initiales du club s'affiche automatiquement à la place — l'app ne
// plante jamais et reste utilisable immédiatement.

struct FavoriteClub: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let assetName: String
    let accentColor: Color

    static let catalog: [FavoriteClub] = [
        // Ligue 1
        FavoriteClub(name: "PSG",        assetName: "crest_psg",        accentColor: Color(hex: "004170")),
        FavoriteClub(name: "OM",         assetName: "crest_om",         accentColor: Color(hex: "2FAEE0")),
        FavoriteClub(name: "OL",         assetName: "crest_ol",         accentColor: Color(hex: "C8102E")),
        FavoriteClub(name: "Monaco",     assetName: "crest_monaco",     accentColor: Color(hex: "E2231A")),
        FavoriteClub(name: "Lille",      assetName: "crest_lille",      accentColor: Color(hex: "C8102E")),
        FavoriteClub(name: "Lens",       assetName: "crest_lens",       accentColor: Color(hex: "FFD100")),
        FavoriteClub(name: "Rennes",     assetName: "crest_rennes",     accentColor: Color(hex: "E2001A")),
        FavoriteClub(name: "Nice",       assetName: "crest_nice",       accentColor: Color(hex: "C8102E")),
        FavoriteClub(name: "Strasbourg", assetName: "crest_strasbourg", accentColor: Color(hex: "0072CE")),
        FavoriteClub(name: "Brest",      assetName: "crest_brest",      accentColor: Color(hex: "DA0E29")),

        // Grands clubs européens
        FavoriteClub(name: "Real Madrid",  assetName: "crest_real_madrid",  accentColor: Color(hex: "FEBE10")),
        FavoriteClub(name: "Barcelone",    assetName: "crest_barcelone",    accentColor: Color(hex: "A50044")),
        FavoriteClub(name: "Man City",     assetName: "crest_man_city",     accentColor: Color(hex: "6CABDD")),
        FavoriteClub(name: "Man United",   assetName: "crest_man_united",   accentColor: Color(hex: "DA291C")),
        FavoriteClub(name: "Liverpool",    assetName: "crest_liverpool",    accentColor: Color(hex: "C8102E")),
        FavoriteClub(name: "Chelsea",      assetName: "crest_chelsea",      accentColor: Color(hex: "034694")),
        FavoriteClub(name: "Arsenal",      assetName: "crest_arsenal",      accentColor: Color(hex: "EF0107")),
        FavoriteClub(name: "Bayern Munich",assetName: "crest_bayern",       accentColor: Color(hex: "DC052D")),
        FavoriteClub(name: "Dortmund",     assetName: "crest_dortmund",     accentColor: Color(hex: "FDE100")),
        FavoriteClub(name: "Juventus",     assetName: "crest_juventus",     accentColor: Color(hex: "000000")),
        FavoriteClub(name: "Inter Milan",  assetName: "crest_inter",        accentColor: Color(hex: "0068A8")),
        FavoriteClub(name: "AC Milan",     assetName: "crest_ac_milan",     accentColor: Color(hex: "FB090B")),
    ]

    static func find(byName name: String) -> FavoriteClub? {
        catalog.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }
}

// MARK: - Vue du blason (avec secours automatique)

struct CrestView: View {
    let crest: FavoriteClub?
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let crest, let uiImage = UIImage(named: crest.assetName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else if let crest {
                // Secours : cercle coloré + initiales (toujours fonctionnel)
                ZStack {
                    Circle().fill(crest.accentColor)
                    Text(initials(crest.name))
                        .font(.system(size: size * 0.36, weight: .black))
                        .foregroundStyle(.white)
                }
            } else {
                Circle().fill(.white.opacity(0.15))
            }
        }
        .frame(width: size, height: size)
    }

    private func initials(_ name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Sheet de sélection (grille de blasons)

struct FavoriteTeamPickerSheet: View {
    @Binding var selectedTeam: String
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(FavoriteClub.catalog) { crest in
                        Button {
                            selectedTeam = crest.name
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                CrestView(crest: crest, size: 52)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                selectedTeam == crest.name ? Pitcha.teal : Color.clear,
                                                lineWidth: 3
                                            )
                                            .padding(-4)
                                    )
                                Text(crest.name)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Pitcha.navy)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Pitcha.background)
            .navigationTitle("Équipe favorite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
                if !selectedTeam.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Retirer") {
                            selectedTeam = ""
                            dismiss()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}
