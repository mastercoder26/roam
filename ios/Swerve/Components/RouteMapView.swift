import MapKit
import SwiftUI

struct RouteMapView: UIViewRepresentable {
    let polyline: String
    let bounds: RouteBounds
    var routeColor: UIColor = .systemBlue

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isRotateEnabled = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = false
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.routeColor = routeColor
        context.coordinator.update(mapView: mapView, polyline: polyline, bounds: bounds)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var renderedPolyline: String?
        var routeColor: UIColor = .systemBlue

        func update(mapView: MKMapView, polyline: String, bounds: RouteBounds) {
            guard renderedPolyline != polyline else { return }
            renderedPolyline = polyline

            CATransaction.begin()
            CATransaction.setAnimationDuration(0.38)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1))

            mapView.removeOverlays(mapView.overlays)

            guard let routePolyline = PolylineDecoder.mkPolyline(from: polyline) else {
                CATransaction.commit()
                return
            }
            mapView.addOverlay(routePolyline)

            let region = region(for: bounds, polyline: polyline)
            mapView.setVisibleMapRect(
                region,
                edgePadding: UIEdgeInsets(top: 32, left: 24, bottom: 32, right: 24),
                animated: true
            )
            CATransaction.commit()
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = routeColor
                renderer.lineWidth = 4.5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        private func region(for bounds: RouteBounds, polyline: String) -> MKMapRect {
            let sw = bounds.mapRect.southwest
            let ne = bounds.mapRect.northeast

            let minLat = min(sw.latitude, ne.latitude)
            let maxLat = max(sw.latitude, ne.latitude)
            let minLng = min(sw.longitude, ne.longitude)
            let maxLng = max(sw.longitude, ne.longitude)

            let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: maxLat, longitude: minLng))
            let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: minLat, longitude: maxLng))
            var rect = MKMapRect(
                x: topLeft.x,
                y: topLeft.y,
                width: bottomRight.x - topLeft.x,
                height: bottomRight.y - topLeft.y
            )

            if rect.isNull || rect.size.width == 0 || rect.size.height == 0 {
                let coords = PolylineDecoder.decode(polyline)
                rect = coords.reduce(MKMapRect.null) { partial, coordinate in
                    let point = MKMapPoint(coordinate)
                    let pointRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
                    return partial.isNull ? pointRect : partial.union(pointRect)
                }
            }

            return rect.isNull ? MKMapRect.world : rect
        }
    }
}

// MARK: - Polyline decoding
enum PolylineDecoder {
    /// Decodes a Google-encoded polyline string into coordinates.
    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        var index = encoded.startIndex
        var latitude: Int32 = 0
        var longitude: Int32 = 0

        while index < encoded.endIndex {
            guard let latResult = decodeComponent(from: encoded, index: &index) else { break }
            latitude += latResult

            guard let lngResult = decodeComponent(from: encoded, index: &index) else { break }
            longitude += lngResult

            coordinates.append(
                CLLocationCoordinate2D(
                    latitude: Double(latitude) / 1e5,
                    longitude: Double(longitude) / 1e5
                )
            )
        }

        return coordinates
    }

    static func mkPolyline(from encoded: String) -> MKPolyline? {
        let coords = decode(encoded)
        guard !coords.isEmpty else { return nil }
        return MKPolyline(coordinates: coords, count: coords.count)
    }

    private static func decodeComponent(from encoded: String, index: inout String.Index) -> Int32? {
        var result: Int32 = 0
        var shift: Int32 = 0
        var byte: Int32

        repeat {
            guard index < encoded.endIndex else { return nil }
            let scalar = encoded[index].asciiValue.map(Int32.init) ?? 0
            index = encoded.index(after: index)
            byte = scalar - 63
            result |= (byte & 0x1F) << shift
            shift += 5
        } while byte >= 0x20

        let delta = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
        return delta
    }
}

#Preview {
    RouteMapView(
        polyline: "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
        bounds: RouteBounds(
            southwest: Coordinate(latitude: 38.5, longitude: -120.2),
            northeast: Coordinate(latitude: 40.7, longitude: -120.95)
        )
    )
    .frame(height: 220)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
}

/// A locally recorded route with incident annotations. The annotations use
/// actual accepted GPS fixes, rather than inferred positions along the line.
struct RecordedDriveMapView: UIViewRepresentable {
    let route: [DriveRoutePoint]
    let events: [DrivingEvent]
    var onSelectEvent: (DrivingEvent) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.showsCompass = false
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onSelectEvent = onSelectEvent
        context.coordinator.update(map: map, route: route, events: events)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelectEvent: onSelectEvent) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelectEvent: (DrivingEvent) -> Void
        private var renderedKey = ""

        init(onSelectEvent: @escaping (DrivingEvent) -> Void) {
            self.onSelectEvent = onSelectEvent
        }

        func update(map: MKMapView, route: [DriveRoutePoint], events: [DrivingEvent]) {
            let key = route.map(\.timestamp).description + events.map(\.id).description
            guard key != renderedKey else { return }
            renderedKey = key
            map.removeOverlays(map.overlays)
            map.removeAnnotations(map.annotations)

            let coordinates = route.map { $0.coordinate.clLocationCoordinate }
            guard !coordinates.isEmpty else { return }
            map.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count))
            for event in events {
                guard let coordinate = event.coordinate?.clLocationCoordinate else { continue }
                let annotation = DriveEventAnnotation(event: event)
                annotation.coordinate = coordinate
                map.addAnnotation(annotation)
            }
            let rect = MKPolyline(coordinates: coordinates, count: coordinates.count).boundingMapRect
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 36, left: 28, bottom: 36, right: 28), animated: false)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? DriveEventAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "drive-event") as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "drive-event")
            view.annotation = annotation
            view.canShowCallout = true
            view.markerTintColor = .systemOrange
            view.glyphImage = UIImage(systemName: annotation.event.kind.symbol)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? DriveEventAnnotation else { return }
            onSelectEvent(annotation.event)
        }
    }
}

private final class DriveEventAnnotation: MKPointAnnotation {
    let event: DrivingEvent

    init(event: DrivingEvent) {
        self.event = event
        super.init()
        title = event.kind.title
        subtitle = "Tap for details"
    }
}
