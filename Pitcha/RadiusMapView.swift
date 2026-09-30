import SwiftUI
import MapKit
import UIKit

/// Aperçu carte non-interactif : un point central + un cercle représentant
/// le rayon de recherche choisi. Pas de pan/zoom manuel — volontairement
/// simple, la zone se choisit via "Autour de moi" ou la recherche
/// d'adresse (VenueSearchField), pas en manipulant la carte.
struct RadiusMapView: UIViewRepresentable {
    var coordinate: CLLocationCoordinate2D
    var radiusMeters: Double

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isUserInteractionEnabled = false
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        let circle = MKCircle(center: coordinate, radius: radiusMeters)
        map.addOverlay(circle)

        let pin = MKPointAnnotation()
        pin.coordinate = coordinate
        map.addAnnotation(pin)

        // Marge de 30% autour du cercle pour qu'il ne touche pas les bords.
        let span = radiusMeters * 2.6
        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: span, longitudinalMeters: span)
        map.setRegion(region, animated: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let circle = overlay as? MKCircle else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKCircleRenderer(circle: circle)
            renderer.fillColor = UIColor(Pitcha.navy).withAlphaComponent(0.16)
            renderer.strokeColor = UIColor(Pitcha.navy)
            renderer.lineWidth = 2
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "center")
            view.markerTintColor = UIColor(Pitcha.teal)
            view.glyphImage = UIImage(systemName: "sportscourt.fill")
            view.canShowCallout = false
            return view
        }
    }
}
