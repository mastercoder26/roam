import MapKit
import SwiftUI

/// The route being analyzed stays visible. A paced trace follows its actual
/// geometry; reducing motion leaves the complete route in place.
struct RouteAnalysisLoadingView: View {
    let isFinishing: Bool
    var coordinates: [Coordinate] = []
    var destination: String = ""
    var routeSummary: String?
    var onCancel: (() -> Void)?
    let onDepartureComplete: () -> Void
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            RouteAnalysisTraceMap(coordinates: coordinates, reduceMotion: reduceMotion)
                .ignoresSafeArea(.container)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Routes")
                    .padding(.top, AppDesign.screenTopPadding)
                Spacer()
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.regular)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isFinishing ? "Route ready" : "Analyzing route")
                                .font(.title3.weight(.semibold))
                            Text([destination, routeSummary].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(AppDesign.Ink.secondary)
                                .lineLimit(2)
                        }
                    }
                    if let onCancel {
                        Button("Cancel", action: onCancel)
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.large)
                            .tint(AppDesign.Ink.primary)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("routes.cancelAnalysis")
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 20)
        }
        .accessibilityIdentifier("routes.analysisLoading")
        .task(id: isFinishing) {
            guard isFinishing else { return }
            do { try await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 250)) }
            catch { return }
            onDepartureComplete()
        }
    }
}

private struct RouteAnalysisTraceMap: UIViewRepresentable {
    let coordinates: [Coordinate]
    let reduceMotion: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isUserInteractionEnabled = false
        map.showsCompass = false
        map.pointOfInterestFilter = .excludingAll
        map.setRegion(RoutePlanningMapPreview.Coordinator.fallbackRegion, animated: false)
        context.coordinator.install(in: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        context.coordinator.setTint(AppDesign.UIKitColor.accent)
        context.coordinator.update(coordinates: coordinates, reduceMotion: reduceMotion, map: map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let base = CAShapeLayer()
        private let trace = CAShapeLayer()
        private let marker = CAShapeLayer()
        private let destination = CAShapeLayer()
        private var coordinates: [CLLocationCoordinate2D] = []
        private var reduceMotion = false
        private var key = ""

        func install(in map: MKMapView) {
            for layer in [base, trace] {
                layer.fillColor = UIColor.clear.cgColor
                layer.lineWidth = 6
                layer.lineCap = .round
                layer.lineJoin = .round
                map.layer.addSublayer(layer)
            }
            base.strokeColor = UIColor.systemBlue.withAlphaComponent(0.2).cgColor
            trace.strokeColor = UIColor.systemBlue.cgColor
            marker.path = UIBezierPath(ovalIn: CGRect(x: -7, y: -7, width: 14, height: 14)).cgPath
            marker.fillColor = UIColor.systemBlue.cgColor
            marker.strokeColor = UIColor.white.cgColor
            marker.lineWidth = 3
            map.layer.addSublayer(marker)
            marker.isHidden = true
            destination.path = UIBezierPath(ovalIn: CGRect(x: -8, y: -8, width: 16, height: 16)).cgPath
            destination.fillColor = UIColor.white.cgColor
            destination.lineWidth = 4
            destination.isHidden = true
            map.layer.addSublayer(destination)
        }

        func setTint(_ color: UIColor) {
            base.strokeColor = color.withAlphaComponent(0.2).cgColor
            trace.strokeColor = color.cgColor
            marker.fillColor = color.cgColor
            destination.strokeColor = color.cgColor
        }

        func update(coordinates values: [Coordinate], reduceMotion: Bool, map: MKMapView) {
            let newKey = values.map { "\($0.latitude),\($0.longitude)" }.joined(separator: ";") + String(reduceMotion)
            guard newKey != key else { return }
            key = newKey
            coordinates = values.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            self.reduceMotion = reduceMotion
            guard coordinates.count > 1 else { return }
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            map.setVisibleMapRect(polyline.boundingMapRect,
                edgePadding: UIEdgeInsets(top: 160, left: 42, bottom: 260, right: 42), animated: false)
            redraw(in: map)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { redraw(in: mapView) }

        private func redraw(in map: MKMapView) {
            guard coordinates.count > 1 else { return }
            let path = UIBezierPath()
            let points = coordinates.map { map.convert($0, toPointTo: map) }
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            base.path = path.cgPath
            trace.path = path.cgPath
            trace.removeAllAnimations()
            marker.removeAllAnimations()
            marker.isHidden = reduceMotion
            marker.position = points[0]
            destination.position = points[points.count - 1]
            destination.isHidden = false
            CATransaction.commit()
            guard !reduceMotion else { return }
            let draw = CAKeyframeAnimation(keyPath: "strokeEnd")
            draw.values = [0, 0, 1, 1]
            draw.keyTimes = [0, 0.08, 0.8, 1]
            draw.duration = 1.8
            draw.repeatCount = .infinity
            trace.add(draw, forKey: "routeTrace")
            let travel = CAKeyframeAnimation(keyPath: "position")
            travel.path = path.cgPath
            travel.calculationMode = .paced
            travel.beginTime = 0.144
            travel.duration = 1.296
            travel.fillMode = .both
            let loop = CAAnimationGroup()
            loop.animations = [travel]
            loop.duration = 1.8
            loop.repeatCount = .infinity
            marker.add(loop, forKey: "routeHead")
        }
    }
}
