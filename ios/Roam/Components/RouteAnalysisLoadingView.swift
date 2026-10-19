import MapKit
import SwiftUI

/// A single trace acts as estimated progress along the actual route geometry.
struct RouteAnalysisLoadingView: View {
    let isFinishing: Bool
    let progress: RouteAnalysisProgress
    var coordinates: [Coordinate] = []
    var destination: String = ""
    var routeSummary: String?
    var onCancel: (() -> Void)?
    let onDepartureComplete: () -> Void
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: scenePhase != .active)) { _ in
            content(at: ProcessInfo.processInfo.systemUptime)
        }
        .accessibilityIdentifier("routes.analysisLoading")
        .task(id: isFinishing) {
            guard isFinishing else { return }
            do { try await Task.sleep(for: .seconds(progress.remainingCompletionTime(at: ProcessInfo.processInfo.systemUptime))) }
            catch { return }
            onDepartureComplete()
        }
    }

    private func content(at time: TimeInterval) -> some View {
        let fraction = progress.fraction(at: time)
        return ZStack(alignment: .bottom) {
            RouteAnalysisTraceMap(coordinates: coordinates, fraction: fraction)
                .ignoresSafeArea(.container)
                .accessibilityHidden(true)
            RouteMapBottomFade().ignoresSafeArea(.container)
            RouteMapHeaderShading().ignoresSafeArea(.container)
            VStack(alignment: .leading, spacing: 16) {
                CompactScreenHeader(title: "Routes")
                Spacer()
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().stroke(AppDesign.accent.opacity(0.18), lineWidth: 3)
                            Circle().trim(from: 0, to: fraction)
                                .stroke(AppDesign.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isFinishing ? "Route ready" : "Analyzing route")
                                .font(.title3.weight(.semibold))
                            Text([destination, routeSummary].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(AppDesign.Ink.secondary)
                                .lineLimit(2)
                            if !isFinishing {
                                Text(progress.timeDescription(at: time))
                                    .font(.caption)
                                    .foregroundStyle(AppDesign.Ink.secondary)
                                    .accessibilityIdentifier("routes.analysisEstimate")
                            }
                        }
                        Spacer(minLength: 0)
                        Text("\(Int(fraction * 100))%")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(AppDesign.Ink.secondary)
                            .accessibilityLabel("Estimated progress")
                            .accessibilityValue("\(Int(fraction * 100)) percent")
                            .accessibilityIdentifier("routes.analysisProgress")
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
    }
}

private struct RouteAnalysisTraceMap: UIViewRepresentable {
    let coordinates: [Coordinate]
    let fraction: Double
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
        context.coordinator.update(coordinates: coordinates, map: map)
        context.coordinator.setProgress(fraction)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let base = CAShapeLayer()
        private let trace = CAShapeLayer()
        private let marker = CAShapeLayer()
        private let destination = CAShapeLayer()
        private var coordinates: [CLLocationCoordinate2D] = []
        private var sourceCoordinates: [Coordinate] = []
        private var geometry = RouteTraceGeometry(points: [])
        private var fraction = 0.0

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
            trace.strokeEnd = 0
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

        func update(coordinates values: [Coordinate], map: MKMapView) {
            guard values != sourceCoordinates else { return }
            sourceCoordinates = values
            coordinates = values.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                .filter { CLLocationCoordinate2DIsValid($0) }
            guard coordinates.count > 1 else {
                base.path = nil
                trace.path = nil
                geometry = RouteTraceGeometry(points: [])
                marker.isHidden = true
                destination.isHidden = true
                return
            }
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            map.setVisibleMapRect(polyline.boundingMapRect,
                edgePadding: UIEdgeInsets(top: 160, left: 42, bottom: 260, right: 42), animated: false)
            redraw(in: map)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { redraw(in: mapView) }
        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) { redraw(in: mapView) }

        func setProgress(_ value: Double) {
            fraction = min(1, max(0, value))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            trace.strokeEnd = fraction
            marker.isHidden = geometry.points.count < 2
            if let point = geometry.position(at: fraction) { marker.position = point }
            CATransaction.commit()
        }

        private func redraw(in map: MKMapView) {
            guard coordinates.count > 1 else { return }
            let path = UIBezierPath()
            let points = coordinates.map { map.convert($0, toPointTo: map) }
            geometry = RouteTraceGeometry(points: points)
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            base.path = path.cgPath
            trace.path = path.cgPath
            destination.position = points[points.count - 1]
            destination.isHidden = false
            CATransaction.commit()
            setProgress(fraction)
        }
    }
}
