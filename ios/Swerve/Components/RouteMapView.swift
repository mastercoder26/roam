import MapKit
import SwiftUI

struct RouteMapView: UIViewRepresentable {
    let polyline: String
    let bounds: RouteBounds
    var routeColor: UIColor = .systemBlue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.update(mapView: mapView, polyline: polyline, bounds: bounds)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var renderedKey: String?
        var routeColor: UIColor = .systemBlue
        var reduceMotion = false

        func update(mapView: MKMapView, polyline: String, bounds: RouteBounds) {
            let renderKey = makeRenderKey(polyline: polyline, bounds: bounds)
            guard renderedKey != renderKey else { return }
            renderedKey = renderKey

            CATransaction.begin()
            if reduceMotion {
                CATransaction.setDisableActions(true)
            } else {
                CATransaction.setAnimationDuration(AppAnimation.mapDuration)
                CATransaction.setAnimationTimingFunction(
                    CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1)
                )
            }

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
                animated: !reduceMotion
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

        private func makeRenderKey(polyline: String, bounds: RouteBounds) -> String {
            let resolvedColor = routeColor.resolvedColor(with: .current)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            let colorKey: String
            if resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                colorKey = "\(red),\(green),\(blue),\(alpha)"
            } else {
                colorKey = resolvedColor.description
            }
            return [
                polyline,
                String(bounds.southwest.latitude),
                String(bounds.southwest.longitude),
                String(bounds.northeast.latitude),
                String(bounds.northeast.longitude),
                colorKey,
            ].joined(separator: "|")
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

/// A locally recorded route with replay annotations. A moment is shown only
/// when its timestamp falls inside a verified continuous GPS segment.
struct RecordedDriveMapView: UIViewRepresentable {
    let route: [DriveRoutePoint]
    let moments: [DriveReplayMoment]
    var selectedEventID: UUID?
    var onSelectMoment: (DriveReplayMoment) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.showsCompass = false
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onSelectMoment = onSelectMoment
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.update(
            map: map,
            route: route,
            moments: moments,
            selectedEventID: selectedEventID
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelectMoment: onSelectMoment) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelectMoment: (DriveReplayMoment) -> Void
        private var renderedKey = ""
        private var selectedEventID: UUID?
        private var annotationsByID: [UUID: DriveReplayAnnotation] = [:]
        var reduceMotion = false

        init(onSelectMoment: @escaping (DriveReplayMoment) -> Void) {
            self.onSelectMoment = onSelectMoment
        }

        func update(
            map: MKMapView,
            route: [DriveRoutePoint],
            moments: [DriveReplayMoment],
            selectedEventID: UUID?
        ) {
            let key = route.map(\.timestamp).description + moments.map(\.id).description
            if key != renderedKey {
                renderedKey = key
                map.removeOverlays(map.overlays)
                map.removeAnnotations(map.annotations)
                annotationsByID = [:]

                let polylines = continuousPolylines(from: route)
                guard !polylines.isEmpty else { return }
                polylines.forEach { map.addOverlay($0) }
                for moment in moments {
                    guard let coordinate = moment.coordinate?.clLocationCoordinate else { continue }
                    let annotation = DriveReplayAnnotation(moment: moment)
                    annotation.coordinate = coordinate
                    annotationsByID[moment.id] = annotation
                    map.addAnnotation(annotation)
                }
                let rect = polylines.reduce(MKMapRect.null) { partial, polyline in
                    partial.isNull ? polyline.boundingMapRect : partial.union(polyline.boundingMapRect)
                }
                map.setVisibleMapRect(
                    rect,
                    edgePadding: UIEdgeInsets(top: 36, left: 28, bottom: 36, right: 28),
                    animated: false
                )
            }

            guard selectedEventID != self.selectedEventID else { return }
            self.selectedEventID = selectedEventID
            updateSelection(in: map)
        }

        /// Never draw a synthetic line across a gap in accepted GPS data. The
        /// same trace segmentation also powers replay interpolation.
        private func continuousPolylines(from route: [DriveRoutePoint]) -> [MKPolyline] {
            let segments = DriveExperienceEngine.validTraceSegments(for: route)
            guard !segments.isEmpty else { return [] }

            var groups: [[CLLocationCoordinate2D]] = []
            var lastEndIndex: Int?
            for segment in segments {
                if lastEndIndex == segment.startIndex, !groups.isEmpty {
                    groups[groups.count - 1].append(segment.end.coordinate.clLocationCoordinate)
                } else {
                    groups.append([
                        segment.start.coordinate.clLocationCoordinate,
                        segment.end.coordinate.clLocationCoordinate,
                    ])
                }
                lastEndIndex = segment.endIndex
            }

            return groups.compactMap { coordinates in
                guard coordinates.count >= 2 else { return nil }
                return MKPolyline(coordinates: coordinates, count: coordinates.count)
            }
        }

        private func updateSelection(in map: MKMapView) {
            for annotation in map.annotations {
                guard let annotation = annotation as? DriveReplayAnnotation,
                      let marker = map.view(for: annotation) as? MKMarkerAnnotationView else { continue }
                marker.markerTintColor = annotation.moment.id == selectedEventID
                    ? .systemBlue
                    : .systemOrange
                marker.displayPriority = annotation.moment.id == selectedEventID
                    ? .required
                    : .defaultHigh
            }

            guard let selectedEventID,
                  let annotation = annotationsByID[selectedEventID] else { return }
            map.selectAnnotation(annotation, animated: !reduceMotion)
            CATransaction.begin()
            if reduceMotion {
                CATransaction.setDisableActions(true)
            } else {
                CATransaction.setAnimationDuration(AppAnimation.mapDuration)
                CATransaction.setAnimationTimingFunction(
                    CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1)
                )
            }
            map.setCenter(annotation.coordinate, animated: !reduceMotion)
            CATransaction.commit()
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
            guard let annotation = annotation as? DriveReplayAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "drive-event") as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "drive-event")
            view.annotation = annotation
            view.canShowCallout = true
            view.markerTintColor = annotation.moment.id == selectedEventID ? .systemBlue : .systemOrange
            view.displayPriority = annotation.moment.id == selectedEventID ? .required : .defaultHigh
            view.glyphImage = UIImage(systemName: annotation.moment.kind.symbol)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? DriveReplayAnnotation else { return }
            onSelectMoment(annotation.moment)
        }
    }
}

private final class DriveReplayAnnotation: MKPointAnnotation {
    let moment: DriveReplayMoment

    init(moment: DriveReplayMoment) {
        self.moment = moment
        super.init()
        title = moment.kind.title
        subtitle = "Tap to review this moment"
    }
}
