import SwiftUI
import MapKit

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
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
                VStack(spacing: 20) {
                    routeForm
                    if isLoading { loadingCard }
                    if let result { resultView(result) }
                }
                .padding()
            }
            .navigationTitle("Swerve")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Backend", systemImage: "gearshape") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) { BackendSettingsView() }
            .alert("Couldn’t score this drive", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private var routeForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Is this a drive they’re ready for?")
                .font(.title2.bold())
            Text("Get a route-specific difficulty assessment before handing over the keys.")
                .foregroundStyle(.secondary)
            TextField("Starting point", text: $origin)
                .textContentType(.fullStreetAddress)
                .textFieldStyle(.roundedBorder)
            TextField("Destination", text: $destination)
                .textContentType(.fullStreetAddress)
                .textFieldStyle(.roundedBorder)
            TextField("Minutes already driven (optional)", text: $priorDriveMinutes)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
            Toggle("Compare alternate routes", isOn: $includeAlternates)
            Button(action: scoreRoute) {
                Label(isLoading ? "Checking route…" : "Check drive difficulty", systemImage: "steeringwheel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading || origin.trimmingCharacters(in: .whitespaces).isEmpty || destination.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Checking traffic, road conditions, and weather…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    @ViewBuilder
    private func resultView(_ response: DifficultyResponse) -> some View {
        let route = response.primaryRoute
        VStack(spacing: 18) {
            scoreHero(route)
            routeMap(route)
            reasonsCard(route)
            if let conditions = route.conditions, conditions.weather.available || conditions.road.available {
                conditionsCard(conditions)
            }
            factorsCard(route)
            hotspotsCard(route)
            if !response.alternateRoutes.isEmpty { alternateRoutes(response.alternateRoutes) }
            safetyNote
        }
    }

    private func scoreHero(_ route: ScoredRoute) -> some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().fill(scoreColor(route.score).gradient)
                Text(String(format: "%.1f", route.score))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 5) {
                Text(route.label).font(.title2.bold())
                Text("Difficulty score · 1–10")
                    .foregroundStyle(.secondary)
                Text("\(route.distanceText) · \(route.durationText)")
                    .font(.subheadline.weight(.medium))
                Text("Likely range \(route.uncertainty.low, specifier: "%.1f")–\(route.uncertainty.high, specifier: "%.1f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(scoreColor(route.score).opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func routeMap(_ route: ScoredRoute) -> some View {
        let coordinates = Polyline.decode(route.polyline)
        return Map(position: $mapPosition) {
            if coordinates.count > 1 {
                MapPolyline(MKPolyline(coordinates: coordinates, count: coordinates.count))
                    .stroke(scoreColor(route.score), lineWidth: 6)
            }
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear { centerMap(on: route.bounds) }
        .onChange(of: route.id) { _, _ in centerMap(on: route.bounds) }
    }

    private func reasonsCard(_ route: ScoredRoute) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Why this route feels harder", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            ForEach(route.reasons, id: \.self) { reason in
                Label(reason, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func conditionsCard(_ conditions: RouteConditions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Conditions", systemImage: "cloud.sun.fill").font(.headline)
            if conditions.weather.available {
                Text("\(conditions.weather.condition) · \(Int(conditions.weather.temperatureF))°F · gusts up to \(Int(conditions.weather.windGustMph)) mph")
            }
            if conditions.road.available {
                Text("Mostly \(conditions.road.dominantRoadClass) roads · \(conditions.road.constructionZones) construction zone\(conditions.road.constructionZones == 1 ? "" : "s")")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func factorsCard(_ route: ScoredRoute) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("What shaped the score", systemImage: "chart.bar.fill").font(.headline)
            ForEach(route.contributions.prefix(5)) { factor in
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(factor.label); Spacer(); Text("\(Int(factor.value * 100))%") .foregroundStyle(.secondary) }
                    ProgressView(value: min(1, factor.value)).tint(scoreColor(route.score))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func hotspotsCard(_ route: ScoredRoute) -> some View {
        guard !route.hotspots.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(VStack(alignment: .leading, spacing: 10) {
            Label("Pay attention here", systemImage: "mappin.and.ellipse").font(.headline)
            ForEach(route.hotspots) { hotspot in
                HStack {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text(hotspot.label ?? "Demanding section")
                    Spacer()
                    Text("\(Int(hotspot.cumulativeSecondsFromStart / 60)) min in")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous)))
    }

    private func alternateRoutes(_ routes: [AlternateRoute]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Other route options", systemImage: "arrow.triangle.swap").font(.headline)
            ForEach(routes) { route in
                HStack {
                    Text("\(route.label) · \(route.score, specifier: "%.1f")")
                    Spacer()
                    Text(route.scoreDelta < 0 ? "\(abs(route.scoreDelta), specifier: "%.1f") easier" : "\(route.scoreDelta, specifier: "+%.1f") harder")
                        .font(.subheadline).foregroundStyle(route.scoreDelta < 0 ? .green : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var safetyNote: some View {
        Text("Swerve supports better planning; it does not replace a parent’s judgment, traffic laws, or attentive driving.")
            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
    }

    private func scoreRoute() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                let minutes = Int(priorDriveMinutes)
                let response = try await DifficultyAPI().score(
                    origin: origin,
                    destination: destination,
                    includeAlternates: includeAlternates,
                    continuousDriveMinutes: minutes,
                    baseURL: settings.backendBaseURL
                )
                withAnimation(.snappy) { result = response }
            } catch { errorMessage = error.localizedDescription }
        }
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
        mapPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func scoreColor(_ score: Double) -> Color {
        score < 4 ? .green : score < 6 ? .yellow : score < 8 ? .orange : .red
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
                    Text("Use http://127.0.0.1:3000 for the server running on this Mac. For a physical phone, use your Mac’s LAN IP instead.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Backend")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

#Preview {
    ContentView().environmentObject(AppSettings())
}
