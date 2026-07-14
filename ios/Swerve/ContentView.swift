import MapKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var origin = ""
    @State private var destination = ""
    @State private var includeAlternates = true
    @State private var priorDriveMinutes = ""
    @State private var result: DifficultyResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var mapPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    introduction
                    routeForm

                    if isLoading {
                        LoadingBrief()
                            .transition(resultTransition)
                    }

                    if let result {
                        AssessmentView(
                            response: result,
                            mapPosition: $mapPosition,
                            reduceMotion: reduceMotion
                        )
                        .transition(resultTransition)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(SwerveTheme.canvas.ignoresSafeArea())
            .navigationTitle("Swerve")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Connection", systemImage: "gearshape") {
                        showSettings = true
                    }
                    .accessibilityLabel("Backend connection settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                BackendSettingsView()
                    .presentationDetents([.medium])
            }
            .alert("Unable to assess this route", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(SwerveTheme.ink)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Know the route\nbefore the drive.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(SwerveTheme.ink)
            Text("A clear read on what will make a trip more demanding.")
                .font(.body)
                .foregroundStyle(SwerveTheme.mutedInk)
        }
        .accessibilityElement(children: .combine)
    }

    private var routeForm: some View {
        VStack(spacing: 0) {
            RouteField(
                title: "From",
                placeholder: "Starting point",
                text: $origin,
                marker: .origin
            )
            .padding(.bottom, 10)

            HStack(spacing: 12) {
                RouteMarker(kind: .connector)
                    .frame(width: 20)
                Divider().overlay(SwerveTheme.line)
            }
            .padding(.vertical, 2)

            RouteField(
                title: "To",
                placeholder: "Destination",
                text: $destination,
                marker: .destination
            )
            .padding(.top, 10)

            Divider().overlay(SwerveTheme.line)
                .padding(.vertical, 18)

            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(SwerveTheme.mutedInk)
                    .frame(width: 20)
                TextField("Minutes already driven", text: $priorDriveMinutes)
                    .keyboardType(.numberPad)
                    .foregroundStyle(SwerveTheme.ink)
                Text("optional")
                    .font(.caption)
                    .foregroundStyle(SwerveTheme.mutedInk)
            }

            Toggle("Compare other routes", isOn: $includeAlternates)
                .font(.subheadline.weight(.medium))
                .padding(.top, 18)

            Button(action: scoreRoute) {
                HStack(spacing: 10) {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up.right")
                    }
                    Text(isLoading ? "Assessing route" : "Assess this route")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(isLoading || origin.trimmed.isEmpty || destination.trimmed.isEmpty)
            .padding(.top, 22)
        }
        .padding(20)
        .background(SwerveTheme.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(SwerveTheme.line, lineWidth: 1)
        }
        .shadow(color: SwerveTheme.ink.opacity(0.06), radius: 20, y: 8)
    }

    private var resultTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
    }

    private func scoreRoute() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                let response = try await DifficultyAPI().score(
                    origin: origin.trimmed,
                    destination: destination.trimmed,
                    includeAlternates: includeAlternates,
                    continuousDriveMinutes: Int(priorDriveMinutes),
                    baseURL: settings.backendBaseURL
                )
                withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.48, dampingFraction: 0.88)) {
                    result = response
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct AssessmentView: View {
    let response: DifficultyResponse
    @Binding var mapPosition: MapCameraPosition
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Route brief")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(SwerveTheme.ink)
            RouteMap(route: response.primaryRoute, position: $mapPosition)
            ScoreSummary(route: response.primaryRoute, reduceMotion: reduceMotion)
            ReasonList(reasons: response.primaryRoute.reasons)

            if let conditions = response.primaryRoute.conditions,
               conditions.weather.available || conditions.road.available {
                ConditionsStrip(conditions: conditions)
            }

            if !response.primaryRoute.hotspots.isEmpty {
                HotspotList(hotspots: response.primaryRoute.hotspots)
            }

            if !response.alternateRoutes.isEmpty {
                AlternateRouteList(routes: response.alternateRoutes)
            }

            Text("Swerve helps with planning. It cannot replace a parent’s judgment, local conditions, or attentive driving.")
                .font(.footnote)
                .foregroundStyle(SwerveTheme.mutedInk)
                .padding(.top, 2)
        }
    }
}

private struct RouteMap: View {
    let route: ScoredRoute
    @Binding var position: MapCameraPosition

    var body: some View {
        let coordinates = Polyline.decode(route.polyline)
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            if coordinates.count > 1 {
                MapPolyline(MKPolyline(coordinates: coordinates, count: coordinates.count))
                    .stroke(SwerveTheme.scoreColor(for: route.score), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted))
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Text("\(route.distanceText)  ·  \(route.durationText)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SwerveTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(14)
        }
        .onAppear { centerMap(on: route.bounds) }
        .onChange(of: route.id) { _, _ in centerMap(on: route.bounds) }
    }

    private func centerMap(on bounds: RouteBounds) {
        let center = CLLocationCoordinate2D(
            latitude: (bounds.southwest.lat + bounds.northeast.lat) / 2,
            longitude: (bounds.southwest.lng + bounds.northeast.lng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, abs(bounds.northeast.lat - bounds.southwest.lat) * 1.35),
            longitudeDelta: max(0.02, abs(bounds.northeast.lng - bounds.southwest.lng) * 1.35)
        )
        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}

private struct ScoreSummary: View {
    let route: ScoredRoute
    let reduceMotion: Bool
    @State private var hasAppeared = false

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            ScoreGauge(score: route.score, animate: hasAppeared && !reduceMotion)
                .frame(width: 98, height: 98)
            VStack(alignment: .leading, spacing: 5) {
                Text(route.label)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(SwerveTheme.ink)
                Text("Drive difficulty")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SwerveTheme.mutedInk)
                Text("Expected range \(route.uncertainty.low, specifier: "%.1f")–\(route.uncertainty.high, specifier: "%.1f")")
                    .font(.footnote)
                    .foregroundStyle(SwerveTheme.mutedInk)
            }
            Spacer(minLength: 0)
        }
        .onAppear { hasAppeared = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(route.label), difficulty \(route.score, specifier: "%.1f") out of 10")
    }
}

private struct ScoreGauge: View {
    let score: Double
    let animate: Bool

    var body: some View {
        ZStack {
            Circle().stroke(SwerveTheme.scoreColor(for: score).opacity(0.14), lineWidth: 9)
            Circle()
                .trim(from: 0, to: animate ? max(0.02, score / 10) : max(0.02, score / 10))
                .stroke(SwerveTheme.scoreColor(for: score), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(animate ? .easeOut(duration: 0.7) : nil, value: animate)
            Text(String(format: "%.1f", score))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(SwerveTheme.ink)
        }
    }
}

private struct ReasonList: View {
    let reasons: [String]

    var body: some View {
        SectionShell(title: "What to expect") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(reasons, id: \.self) { reason in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(SwerveTheme.signal).frame(width: 6, height: 6)
                        Text(reason).foregroundStyle(SwerveTheme.ink)
                    }
                }
            }
        }
    }
}

private struct ConditionsStrip: View {
    let conditions: RouteConditions

    var body: some View {
        SectionShell(title: "Along the way") {
            HStack(alignment: .top, spacing: 18) {
                if conditions.weather.available {
                    ConditionItem(
                        symbol: weatherSymbol,
                        value: conditions.weather.condition,
                        detail: "\(Int(conditions.weather.temperatureF))°F"
                    )
                }
                if conditions.road.available {
                    ConditionItem(
                        symbol: "road.lanes",
                        value: conditions.road.dominantRoadClass.capitalized,
                        detail: conditions.road.constructionZones > 0 ? "Construction ahead" : "Road mix"
                    )
                }
            }
        }
    }

    private var weatherSymbol: String {
        switch conditions.weather.condition.lowercased() {
        case let condition where condition.contains("rain"): "cloud.rain"
        case let condition where condition.contains("snow"): "cloud.snow"
        case let condition where condition.contains("fog"): "cloud.fog"
        case let condition where condition.contains("storm"): "cloud.bolt.rain"
        default: "cloud.sun"
        }
    }
}

private struct ConditionItem: View {
    let symbol: String
    let value: String
    let detail: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).foregroundStyle(SwerveTheme.signal)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(SwerveTheme.ink)
                Text(detail).font(.caption).foregroundStyle(SwerveTheme.mutedInk)
            }
        }
    }
}

private struct HotspotList: View {
    let hotspots: [SegmentHotspot]

    var body: some View {
        SectionShell(title: "Attention points") {
            VStack(spacing: 0) {
                ForEach(hotspots) { hotspot in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(Int(hotspot.cumulativeSecondsFromStart / 60) + 1) min")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SwerveTheme.signal)
                            .frame(width: 42, alignment: .leading)
                        Text(hotspot.label ?? "Demanding section")
                            .foregroundStyle(SwerveTheme.ink)
                        Spacer(minLength: 8)
                        Text("\(Int(hotspot.difficulty * 100))%")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SwerveTheme.mutedInk)
                    }
                    .padding(.vertical, 12)
                    if hotspot.id != hotspots.last?.id { Divider().overlay(SwerveTheme.line) }
                }
            }
        }
    }
}

private struct AlternateRouteList: View {
    let routes: [AlternateRoute]

    var body: some View {
        SectionShell(title: "Other ways there") {
            VStack(spacing: 0) {
                ForEach(routes) { route in
                    HStack(spacing: 10) {
                        Text("Difficulty \(route.score, specifier: "%.1f")")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SwerveTheme.ink)
                        Spacer()
                        Text(route.scoreDelta < 0 ? "\(abs(route.scoreDelta), specifier: "%.1f") easier" : "\(route.scoreDelta, specifier: "+%.1f") harder")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(route.scoreDelta < 0 ? SwerveTheme.safe : SwerveTheme.mutedInk)
                    }
                    .padding(.vertical, 12)
                    if route.id != routes.last?.id { Divider().overlay(SwerveTheme.line) }
                }
            }
        }
    }
}

private struct LoadingBrief: View {
    var body: some View {
        HStack(spacing: 13) {
            ProgressView().tint(SwerveTheme.signal)
            VStack(alignment: .leading, spacing: 2) {
                Text("Reading the road")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SwerveTheme.ink)
                Text("Traffic, weather, and route complexity")
                    .font(.footnote)
                    .foregroundStyle(SwerveTheme.mutedInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SwerveTheme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct RouteField: View {
    enum Marker { case origin, destination }
    let title: String
    let placeholder: String
    @Binding var text: String
    let marker: Marker

    var body: some View {
        HStack(spacing: 12) {
            RouteMarker(kind: marker == .origin ? .origin : .destination)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.bold)).foregroundStyle(SwerveTheme.mutedInk)
                TextField(placeholder, text: $text)
                    .textContentType(.fullStreetAddress)
                    .autocorrectionDisabled()
                    .foregroundStyle(SwerveTheme.ink)
            }
        }
    }
}

private struct RouteMarker: View {
    enum Kind { case origin, connector, destination }
    let kind: Kind

    var body: some View {
        switch kind {
        case .origin:
            Circle().stroke(SwerveTheme.ink, lineWidth: 2.5).frame(width: 12, height: 12)
        case .connector:
            Rectangle().fill(SwerveTheme.line).frame(width: 2, height: 14)
        case .destination:
            RoundedRectangle(cornerRadius: 3).fill(SwerveTheme.signal).frame(width: 12, height: 12)
        }
    }
}

private struct SectionShell<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(SwerveTheme.ink)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .background(SwerveTheme.ink.opacity(configuration.isPressed ? 0.88 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct BackendSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Difficulty API") {
                    TextField("Backend URL", text: $settings.backendBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("For Simulator, use http://127.0.0.1:3000. A physical phone needs your Mac’s LAN address.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Connection")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private enum SwerveTheme {
    static let canvas = Color(red: 0.96, green: 0.95, blue: 0.91)
    static let paper = Color(red: 0.995, green: 0.99, blue: 0.97)
    static let ink = Color(red: 0.08, green: 0.12, blue: 0.15)
    static let mutedInk = Color(red: 0.33, green: 0.36, blue: 0.36)
    static let line = Color(red: 0.84, green: 0.83, blue: 0.78)
    static let signal = Color(red: 0.83, green: 0.28, blue: 0.12)
    static let safe = Color(red: 0.12, green: 0.43, blue: 0.27)

    static func scoreColor(for score: Double) -> Color {
        switch score {
        case ..<4: safe
        case ..<6: Color(red: 0.73, green: 0.51, blue: 0.07)
        case ..<8: Color(red: 0.78, green: 0.31, blue: 0.08)
        default: Color(red: 0.66, green: 0.15, blue: 0.13)
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

#Preview {
    ContentView().environmentObject(AppSettings())
}
