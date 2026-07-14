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
