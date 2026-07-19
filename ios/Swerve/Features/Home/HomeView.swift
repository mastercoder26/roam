import SwiftUI

struct HomeView: View {
    @State private var origin = ""
    @State private var destination = ""
    @State private var usesCurrentLocation = true
    @State private var departureTime = Date().addingTimeInterval(15 * 60)
    @State private var isLoading = false
    @State private var isCompletingLoading = false
    @State private var pendingResult: RouteAnalysisResult?
    @State private var errorMessage: String?
    @State private var navigationPath = NavigationPath()
    @State private var isOriginAutocompleteVisible = false
    @StateObject private var locationCoordinator = RoutePlanningLocationCoordinator()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let apiClient = APIClient()

    private var canEnterDestination: Bool {
        !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canAnalyze: Bool {
        canEnterDestination && !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                        headerSection
                        routeCard
                        if canEnterDestination { departureCard }
                        if let errorMessage { errorBanner(errorMessage).transition(.opacity.combined(with: .move(edge: .top))) }
                        PrimaryActionButton(title: "Analyze Difficulty", isLoading: isLoading, isEnabled: canAnalyze) {
                            Task { await analyzeRoute() }
                        }
                        .padding(.top, 4)
                        howItWorksSection
                    }
                    .padding(.horizontal, AppDesign.contentPadding)
                    .padding(.vertical, 12)
                }
                .background(Color(.systemGroupedBackground))
                .animation(AppAnimation.quick, value: errorMessage)

                if isLoading {
                    RouteAnalysisLoadingView(isFinishing: isCompletingLoading) { completeLoading() }
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .navigationTitle("Swerve")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: RouteAnalysisResult.self) { ResultsView(result: $0) }
            .onChange(of: locationCoordinator.state) { _, state in
                if case .resolved(let address) = state { origin = address }
            }
            .onAppear {
                guard usesCurrentLocation, origin.isEmpty else { return }
                locationCoordinator.useCurrentLocation()
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Find your calmest route").font(AppDesign.Typography.heroTitle).tracking(-0.7)
            Text("Start where you are, then see what the road asks of you.").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Where?", subtitle: "Search your destination and choose how Swerve should start the route.")
            destinationFirstField
            startingPointSelector
        }
        .premiumCard()
    }


    private var destinationFirstField: some View {
        AddressSearchField(
            title: "Destination",
            placeholder: "Search destinations",
            systemImage: "magnifyingglass",
            iconColor: .secondary,
            text: $destination
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous)
                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
        }
    }

    private var startingPointSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Starting point")
                        .font(.subheadline.weight(.semibold))
                    Text(usesCurrentLocation ? "Use your current location" : "Use a specific address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Starting point", selection: $usesCurrentLocation) {
                    Text("Current").tag(true)
                    Text("Address").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 190)
            }

            if usesCurrentLocation {
                Button {
                    locationCoordinator.useCurrentLocation()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(AppDesign.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentLocationTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Swerve will fill the route from where you are.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if case .locating = locationCoordinator.state {
                            ProgressView().tint(AppDesign.accent)
                        }
                    }
                    .padding(14)
                    .background(AppDesign.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
                }
                .buttonStyle(PressableScaleStyle())
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                originField
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.18) : AppAnimation.content, value: usesCurrentLocation)
    }

    private var currentLocationTitle: String {
        switch locationCoordinator.state {
        case .locating:
            return "Finding current location"
        case .resolved(let address):
            return address
        case .manualEntry(let message):
            return message ?? "Current location unavailable"
        case .awaitingOrigin:
            return origin.isEmpty ? "Current location" : origin
        }
    }

    private var oldRouteFields: some View {
        HStack(alignment: .top, spacing: 10) {
            RouteConnector(
                showDestination: canEnterDestination,
                isOriginAutocompleteVisible: isOriginAutocompleteVisible
            )
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 12) {
                originField
                if canEnterDestination {
                    AddressSearchField(title: "Destination", placeholder: "Where are you going?", systemImage: "flag.fill", iconColor: .red, showsIcon: false, text: $destination)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : AppAnimation.spring, value: canEnterDestination)
    }

    private var originField: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .manualEntry(let message) = locationCoordinator.state, let message {
                Label(message, systemImage: "info.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                AddressSearchField(
                    title: "Starting location",
                    placeholder: "Enter starting address",
                    systemImage: "circle.fill",
                    iconColor: AppDesign.accent,
                    showsIcon: false,
                    text: $origin,
                    onSuggestionsVisibilityChanged: { isOriginAutocompleteVisible = $0 }
                )

                Button { locationCoordinator.useCurrentLocation() } label: {
                    Group {
                        if case .locating = locationCoordinator.state {
                            ProgressView().tint(AppDesign.accent)
                        } else {
                            Image(systemName: "location.fill")
                        }
                    }
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(AppDesign.accent)
                .accessibilityLabel("Use current location")
                .accessibilityHint("Fills the starting location with your current address")
            }
        }
    }

    private var departureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Departure", subtitle: "Traffic estimates use your departure time.")
            DatePicker("When", selection: $departureTime, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact).labelsHidden()
        }.premiumCard()
    }

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "How Swerve scores a route", subtitle: "The road conditions behind each score.")
            FactorExplanationRow(symbol: "speedometer", title: "Speed & highways", detail: "High-speed segments and long highway runs.")
            FactorExplanationRow(symbol: "arrow.triangle.merge", title: "Merges & lane changes", detail: "Interchanges, ramps, and urgent lane decisions.")
            FactorExplanationRow(symbol: "arrow.triangle.turn.up.right.diamond.fill", title: "Turns & decisions", detail: "Maneuver density, turn clusters, and unprotected lefts.")
            FactorExplanationRow(symbol: "car.2.fill", title: "Traffic & trip load", detail: "Live congestion, drive duration, and sustained attention.")
            FactorExplanationRow(symbol: "cloud.sun.rain.fill", title: "Conditions & roads", detail: "Weather, visibility, construction, and road geometry when available.")
            Label("Missing live or road data is left out. Swerve never guesses.", systemImage: "checkmark.shield.fill").font(.footnote).foregroundStyle(.secondary)
        }.premiumCard()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.padding(14).background(Color.red.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
    }

    private func analyzeRoute() async {
        withAnimation(AppAnimation.quick) { errorMessage = nil }
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : AppAnimation.quick) {
            isLoading = true
        }
        do {
            let response = try await apiClient.analyzeRoute(origin: origin, destination: destination, departureTime: departureTime, includeAlternates: true)
            pendingResult = RouteAnalysisResult(
                origin: origin,
                destination: destination,
                departureTime: departureTime,
                primaryRoute: response.primaryRoute,
                alternateRoutes: response.alternateRoutes
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : AppAnimation.quick) {
                isCompletingLoading = true
            }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(AppAnimation.quick) {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func completeLoading() {
        guard let pendingResult else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : AppAnimation.quick) {
            isCompletingLoading = false
            isLoading = false
            self.pendingResult = nil
        }
        navigationPath.append(pendingResult)
    }
}

private struct RouteConnector: View {
    let showDestination: Bool
    let isOriginAutocompleteVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showDestinationIndicator: Bool { showDestination && !isOriginAutocompleteVisible }

    var body: some View {
        VStack(spacing: 0) {
            Circle().fill(AppDesign.accent).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 3))
            // This fixed segment matches the origin row + 12pt inter-row gap,
            // keeping the flag centered on the destination text field.
            VStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: 3, height: 3)
                        .opacity(showDestinationIndicator ? 1 : 0)
                        .animation(dotAnimation(for: index), value: showDestinationIndicator)
                }
            }
            .frame(height: 32)
            Image(systemName: "flag.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
                // The glyph is visually top-heavy, so center its drawing—not
                // merely its text line—against the destination input.
                .frame(width: 12, height: 12)
                .offset(y: 3)
                .opacity(showDestinationIndicator ? 1 : 0)
                .animation(flagAnimation, value: showDestinationIndicator)
        }
        .padding(.top, 11)
        .accessibilityHidden(true)
    }

    private func dotAnimation(for index: Int) -> Animation? {
        guard !reduceMotion else { return .easeOut(duration: 0.15) }
        return AppAnimation.spring.delay(Double(index) * 0.08)
    }

    private var flagAnimation: Animation? {
        guard !reduceMotion else { return .easeOut(duration: 0.15) }
        return AppAnimation.spring.delay(0.36)
    }
}

private struct FactorExplanationRow: View {
    let symbol: String; let title: String; let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.weight(.semibold)); Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct RouteAnalysisResult: Hashable {
    let origin: String
    let destination: String
    let departureTime: Date
    let primaryRoute: ScoredRoute
    let alternateRoutes: [ScoredRoute]
}

#Preview { HomeView() }
