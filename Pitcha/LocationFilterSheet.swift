import SwiftUI
import MapKit

/// Remplace l'ancien Menu de villes fixes dans MatchsView.swift.
/// Affiche : bouton "Autour de moi" (GPS), rayon ajustable avec aperçu
/// carte, et une recherche manuelle (VenueSearchField) pour centrer
/// ailleurs qu'à sa position réelle (ex : voir les matchs dans la ville où
/// on va jouer).
struct LocationFilterButton: View {
    @ObservedObject var viewModel: MatchsViewModel
    @State private var showSheet = false

    /// Icône seule (comme l'ancien bouton "villes") — un texte de ville
    /// à côté allongeait trop le bouton et poussait les pastilles
    /// Publics/Privés/Tournois hors de l'écran.
    var body: some View {
        Button {
            showSheet = true
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(viewModel.searchCenter == nil ? Pitcha.navy : .white)
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(
                        viewModel.searchCenter == nil
                            ? AnyShapeStyle(Color.black.opacity(0.06))
                            : AnyShapeStyle(Pitcha.gradient)
                    )
                )
        }
        .sheet(isPresented: $showSheet) {
            LocationFilterSheet(viewModel: viewModel)
                .presentationDetents([.height(560)])
                .presentationDragIndicator(.visible)
        }
    }
}

/// Reprend la logique globale de l'écran "Zone" de Poteau (adresse
/// éditable en haut, carte avec cercle de rayon, pastilles de distance en
/// bas), simplifiée pour Pitcha : pas de carte à faire glisser — la zone
/// se choisit uniquement via "Autour de moi" ou la recherche d'adresse.
private struct LocationFilterSheet: View {
    @ObservedObject var viewModel: MatchsViewModel
    @StateObject private var locationManager = LocationManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var manualAddress = ""
    @State private var manualCoordinate: CLLocationCoordinate2D?
    @State private var isEditingAddress = false

    /// Paris par défaut tant qu'aucune zone n'est choisie, pour ne pas
    /// afficher une carte vide.
    private static let defaultCenter = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)

    private var displayCenter: CLLocationCoordinate2D {
        manualCoordinate ?? viewModel.searchCenter ?? Self.defaultCenter
    }

    private var displayLabel: String {
        viewModel.searchCenter == nil ? "Choisis une zone" : viewModel.searchCenterLabel
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Zone")
                .font(.title3.weight(.heavy))
                .foregroundStyle(Pitcha.navy)
                .frame(maxWidth: .infinity, alignment: .leading)

            addressCard
            mapPreview
            radiusPicker
            actionsRow

            if let error = locationManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .onAppear { manualAddress = viewModel.searchCenterLabel }
    }

    // MARK: - Adresse (statique + pencil, ou recherche active)

    private var addressCard: some View {
        Group {
            if isEditingAddress {
                VenueSearchField(
                    address: $manualAddress,
                    coordinate: Binding(
                        get: { manualCoordinate },
                        set: { newValue in
                            manualCoordinate = newValue
                            // CLLocationCoordinate2D n'est pas Equatable sur tous les
                            // SDK : on déclenche ici directement au lieu d'un .onChange.
                            if let newValue {
                                viewModel.setManualCenter(newValue, label: manualAddress)
                                isEditingAddress = false
                            }
                        }
                    ),
                    placeholder: "Cherche une ville ou une adresse"
                )
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                HStack(spacing: 0) {
                    Text(displayLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Pitcha.navy)
                        .lineLimit(1)
                        .padding(.leading, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        isEditingAddress = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Pitcha.navy)
                    }
                }
                .frame(height: 52)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06)))
            }
        }
    }

    // MARK: - Carte + cercle de rayon

    @ViewBuilder
    private var mapPreview: some View {
        if viewModel.radius == .all {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.04))
                .frame(height: 150)
                .overlay(
                    Text("Tous les matchs, peu importe la distance")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                )
        } else {
            RadiusMapView(coordinate: displayCenter, radiusMeters: viewModel.radius.rawValue * 1000)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: - Pastilles de rayon

    private var radiusPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchRadius.allCases) { r in
                    Button {
                        withAnimation(.snappy) { viewModel.radius = r }
                    } label: {
                        Text(r.label)
                            .font(.caption.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(viewModel.radius == r
                                               ? AnyShapeStyle(Pitcha.navy)
                                               : AnyShapeStyle(Color.black.opacity(0.06)))
                            )
                            .foregroundStyle(viewModel.radius == r ? .white : Pitcha.navy)
                    }
                }
            }
        }
    }

    // MARK: - Autour de moi / Réinitialiser

    private var actionsRow: some View {
        HStack {
            Button {
                viewModel.useMyLocation()
            } label: {
                HStack(spacing: 6) {
                    if locationManager.isResolving {
                        ProgressView().tint(Pitcha.navy)
                    } else {
                        Image(systemName: "location.fill")
                    }
                    Text(locationManager.isResolving ? "Localisation..." : "Autour de moi")
                }
                .font(.subheadline.bold())
                .foregroundStyle(Pitcha.navy)
            }

            Spacer()

            if viewModel.searchCenter != nil {
                Button("Réinitialiser") {
                    viewModel.clearLocationFilter()
                    manualCoordinate = nil
                    manualAddress = ""
                }
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            }
        }
    }
}
