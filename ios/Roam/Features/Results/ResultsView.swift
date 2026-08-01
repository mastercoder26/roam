import SwiftUI
import UIKit

struct ResultsView: View {
    @State private var result: RouteAnalysisResult

    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var driveSession: DriveSessionManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedRoute: ScoredRoute
    @State private var readinessAssessment: DriverReadinessAssessment
    @State private var routeChoiceRanking: RouteChoiceRanking?
    @State private var routeChoiceCacheKey: RouteChoiceRankingCacheKey?
    @State private var practicePlan: PracticePlan?
    @State private var departureComparison: DepartureComparisonResponse?
    @State private var departureComparisonError: String?
    @State private var isComparingDepartures = false
    @State private var isReanalyzingDeparture = false
    @State private var heroAppeared = false
    @State private var showsAllReadinessEvidence = false

    private let apiClient = APIClient()

    init(result: RouteAnalysisResult) {
        _result = State(initialValue: result)
        _selectedRoute = State(initialValue: result.primaryRoute)
        // This initial placeholder is immediately refreshed from the shared
        // local history on appearance. Caching prevents the GPS-overlap work
        // from running repeatedly while SwiftUI lays out this screen.
        _readinessAssessment = State(
            initialValue: DriverReadinessEngine.assess(
                route: result.primaryRoute,
                recordedDrives: []
            )
        )
    }

    private var routeChoices: [RankedRouteChoice] {
        routeChoiceRanking?.choices ?? []
    }

    private var labelColor: Color {
        selectedRoute.label.color
    }

    private var readiness: DriverReadinessAssessment {
        readinessAssessment
    }

    private var driveHistoryIDs: [UUID] {
        driveSession.recordedDrives.map(\.id)
    }

    private var calmestDepartureID: String? {
        guard let departureComparison else { return nil }
        return DepartureComparisonRanking.calmestCandidateID(in: departureComparison.candidates)
    }

    private var visibleRouteDemands: [RouteDemand] {
        (selectedRoute.routeDemands ?? [])
            .filter { demand in
                demand.available && demand.level != .low
            }
            .sorted { $0.intensity > $1.intensity }
    }

    private var orderedReadinessInsights: [DriverReadinessInsight] {
        readiness.insights.sorted { lhs, rhs in
            let leftPriority = readinessPriority(lhs.state)
            let rightPriority = readinessPriority(rhs.state)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            return lhs.title < rhs.title
        }
    }

    private var featuredReadinessInsights: [DriverReadinessInsight] {
        let actionItems = orderedReadinessInsights.filter {
            $0.state == .practiceNeeded || $0.state == .unmeasured
        }
        guard !showsAllReadinessEvidence else { return orderedReadinessInsights }

        // Never hide a meaningful gap. Only supporting matches are collapsed.
        let remainingSlots = max(0, 4 - actionItems.count)
        let supporting = orderedReadinessInsights.filter {
            $0.state != .practiceNeeded && $0.state != .unmeasured
        }
        return actionItems + supporting.prefix(remainingSlots)
    }

    private var hiddenReadinessInsightCount: Int {
        max(0, orderedReadinessInsights.count - featuredReadinessInsights.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                scoreSection
                    .heroAppear(visible: heroAppeared)

                readinessSection
                    .heroAppear(visible: heroAppeared, delay: AppAnimation.heroStagger)

                departureComparisonSection
                    .heroAppear(visible: heroAppeared, delay: AppAnimation.heroStagger * 2)

                routeChoicesSection
                    .heroAppear(visible: heroAppeared, delay: AppAnimation.heroStagger * 2)

                mapSection
                    .heroAppear(visible: heroAppeared, delay: AppAnimation.heroStagger * 3)

                tripDetailsSection
                routeDemandsSection
                if let conditions = selectedRoute.conditions, !conditions.sources.isEmpty {
                    conditionsSection(conditions)
                }
                navigationSection
                if let hotspots = selectedRoute.hotspots, !hotspots.isEmpty {
                    hotspotsSection(hotspots)
                }
                if selectedRoute.routeDemands == nil {
                    // Keep older backend deployments useful instead of hiding
                    // the prior score explanation while they catch up.
                    breakdownSection
                    if let contributions = selectedRoute.contributions, !contributions.isEmpty {
                        contributionsSection(contributions)
                    }
                    reasonsSection
                }

            }
            .padding(.horizontal, AppDesign.contentPadding)
            .padding(.vertical, 12)
        }
        .background(AppDesign.canvas)
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            heroAppeared = true
            refreshRouteChoices()
            startDepartureComparison()
        }
        .onChange(of: selectedRoute.polyline) { _, _ in
            refreshReadiness()
        }
        .onChange(of: driveHistoryIDs) { _, _ in
            refreshRouteChoices()
        }
    }

    private var scoreSection: some View {
        VStack(spacing: 12) {
            ScoreGaugeView(score: selectedRoute.score, label: selectedRoute.label)

            Text(selectedRoute.label.rawValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(labelColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(labelColor.opacity(0.12))
                .clipShape(Capsule())
                .animation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.selection, value: selectedRoute.label)

            if selectedRoute.uncertainty != nil {
                Text(selectedRoute.formattedScoreWithUncertainty)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if let confidence = selectedRoute.uncertainty?.confidence {
                    Text(String(format: "%.0f%% confidence", confidence * 100))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var readinessSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Can I drive this?",
                subtitle: "Compared with drives recorded privately on this phone."
            )

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: readinessSymbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(readinessColor)
                    .frame(width: 42, height: 42)
                    .background(readinessColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(readiness.headline)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(readiness.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ReadinessHistorySummary(profile: readiness.profile)

            if !featuredReadinessInsights.isEmpty {
                Divider()
                VStack(spacing: 10) {
                    ForEach(featuredReadinessInsights) { insight in
                        ReadinessInsightRow(insight: insight)
                    }
                }
            }

            if hiddenReadinessInsightCount > 0 || showsAllReadinessEvidence {
                Button {
                    withAnimation(AppAnimation.quick) {
                        showsAllReadinessEvidence.toggle()
                    }
                } label: {
                    Label(
                        showsAllReadinessEvidence
                            ? "Show fewer comparisons"
                            : "See all \(orderedReadinessInsights.count) comparisons",
                        systemImage: showsAllReadinessEvidence
                            ? "chevron.up"
                            : "chevron.down"
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppDesign.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    showsAllReadinessEvidence
                        ? "Collapses the recorded evidence used in this route comparison."
                        : "Expands the recorded evidence used in this route comparison."
                )
            }

            if let practicePlan, !practicePlan.goals.isEmpty {
                Divider()
                PracticePlanPreview(plan: practicePlan)
            }

            if !(selectedRoute.routeDemands ?? []).isEmpty {
                Divider()
                Button {
                    queuePracticeRoute()
                } label: {
                    Label("Practice this route", systemImage: "steeringwheel")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(AppDesign.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableScaleStyle())
                .disabled(driveSession.isRecording)
                .opacity(driveSession.isRecording ? 0.55 : 1)
                .accessibilityHint("Prepares this route for your next manually started drive. It does not begin recording.")
            }

            Label(
                "This is coaching, not a safety guarantee.",
                systemImage: "checkmark.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .premiumCard()
        .animation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.content, value: selectedRoute.polyline)
    }

    @ViewBuilder
    private var routeDemandsSection: some View {
        if selectedRoute.routeDemands != nil {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "What this route asks of you",
                    subtitle: "The road conditions that stand out for this drive."
                )

                if visibleRouteDemands.isEmpty {
                    Label(
                        "No route demand stands out above its usual range.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(visibleRouteDemands) { demand in
                            RouteDemandRow(demand: demand)
                            if demand.id != visibleRouteDemands.last?.id {
                                Divider().padding(.leading, 48)
                            }
                        }
                    }
                }

                if selectedRoute.routeDemands?.contains(where: { !$0.available }) == true {
                    Label(
                        "Unavailable live road or weather data is left out rather than estimated.",
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .premiumCard()
            .animation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.content, value: selectedRoute.polyline)
        }
    }

    private var readinessColor: Color {
        switch readiness.verdict {
        case .looksLikeMatch:
            return AppDesign.positive
        case .practiceWithAdult:
            return AppDesign.safety
        case .insufficientHistory:
            return AppDesign.accent
        }
    }

    private var readinessSymbol: String {
        switch readiness.verdict {
        case .looksLikeMatch:
            return "chart.bar.fill"
        case .practiceWithAdult:
            return "figure.and.child.holdinghands"
        case .insufficientHistory:
            return "road.lanes"
        }
    }

    private func queuePracticeRoute() {
        guard !driveSession.isRecording else { return }
        driveSession.queuePlannedPracticeRoute(selectedRoute, practicePlan: practicePlan)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func readinessPriority(_ state: DriverReadinessInsightState) -> Int {
        switch state {
        case .practiceNeeded: return 0
        case .unmeasured: return 1
        case .matched: return 2
        case .informational: return 3
        }
    }

    private func refreshReadiness() {
        let assessment = DriverReadinessEngine.assess(
            route: selectedRoute,
            recordedDrives: driveSession.recordedDrives
        )
        readinessAssessment = assessment
        practicePlan = PracticePlanEngine.makePlan(assessment: assessment, route: selectedRoute)
        showsAllReadinessEvidence = false
    }

    private func refreshRouteChoices(force: Bool = false) {
        let key = RouteChoiceRankingEngine.cacheKey(
            primaryRoute: result.primaryRoute,
            alternateRoutes: result.alternateRoutes,
            recordedDrives: driveSession.recordedDrives
        )
        guard force || key != routeChoiceCacheKey else {
            refreshReadiness()
            return
        }

        let ranking = RouteChoiceRankingEngine.rank(
            primaryRoute: result.primaryRoute,
            alternateRoutes: result.alternateRoutes,
            recordedDrives: driveSession.recordedDrives
        )
        let selectedID = ranking.selectedRouteID(preserving: selectedRoute.id)
        routeChoiceCacheKey = key
        routeChoiceRanking = ranking
        if let selectedChoice = ranking.choice(for: selectedID) {
            selectedRoute = selectedChoice.route
            readinessAssessment = selectedChoice.assessment
            practicePlan = PracticePlanEngine.makePlan(
                assessment: selectedChoice.assessment,
                route: selectedChoice.route
            )
        } else {
            refreshReadiness()
        }
        showsAllReadinessEvidence = false
    }

    private func selectRouteChoice(_ choice: RankedRouteChoice) {
        guard selectedRoute.id != choice.route.id else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.selection) {
            selectedRoute = choice.route
            readinessAssessment = choice.assessment
            practicePlan = PracticePlanEngine.makePlan(assessment: choice.assessment, route: choice.route)
            showsAllReadinessEvidence = false
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func startDepartureComparison() {
        let current = result
        isComparingDepartures = true
        departureComparisonError = nil
        departureComparison = nil

        Task {
            do {
                let response = try await apiClient.compareDepartureTimes(
                    origin: current.origin,
                    destination: current.destination,
                    selectedDeparture: current.departureTime
                )
                guard result.origin == current.origin,
                      result.destination == current.destination,
                      result.departureTime == current.departureTime else {
                    return
                }
                departureComparison = response
            } catch {
                guard result.origin == current.origin,
                      result.destination == current.destination,
                      result.departureTime == current.departureTime else {
                    return
                }
                departureComparisonError = error.localizedDescription
            }
            guard result.origin == current.origin,
                  result.destination == current.destination,
                  result.departureTime == current.departureTime else {
                return
            }
            isComparingDepartures = false
        }
    }

    private func reanalyze(at candidate: DepartureComparisonCandidateResult) {
        guard let departure = candidate.departureDate,
              !isReanalyzingDeparture else { return }
        let current = result
        isReanalyzingDeparture = true

        Task {
            do {
                let response = try await apiClient.analyzeRoute(
                    origin: current.origin,
                    destination: current.destination,
                    departureTime: departure,
                    includeAlternates: true
                )
                let updated = RouteAnalysisResult(
                    origin: current.origin,
                    destination: current.destination,
                    departureTime: departure,
                    primaryRoute: response.primaryRoute,
                    alternateRoutes: response.alternateRoutes
                )
                withAnimation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.content) {
                    result = updated
                    selectedRoute = response.primaryRoute
                    routeChoiceRanking = nil
                    routeChoiceCacheKey = nil
                }
                refreshRouteChoices(force: true)
                startDepartureComparison()
            } catch {
                departureComparisonError = "Could not refresh this departure time. \(error.localizedDescription)"
            }
            isReanalyzingDeparture = false
        }
    }

    private var mapSection: some View {
        RouteMapView(
            polyline: selectedRoute.polyline,
            bounds: selectedRoute.bounds,
            routeColor: UIColor(labelColor)
        )
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
        .animation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.selection, value: selectedRoute.polyline)
    }

    private var tripDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Trip at a glance", subtitle: "The essentials before you choose a route.")

            HStack(spacing: 16) {
                detailTile(
                    title: "ETA",
                    value: selectedRoute.formattedDuration,
                    systemImage: "clock.fill"
                )

                if let delay = selectedRoute.formattedDelay {
                    detailTile(
                        title: "Delay",
                        value: delay,
                        systemImage: "car.fill",
                        valueColor: .orange
                    )
                }

                detailTile(
                    title: "Distance",
                    value: selectedRoute.formattedDistance,
                    systemImage: "arrow.left.and.right"
                )
            }

            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .foregroundStyle(.secondary)
                Text("Normal drive: \(selectedRoute.formattedStaticDuration)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .premiumCard()
    }

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Start Navigation")

            HStack(spacing: 12) {
                Button {
                    openInAppleMaps()
                } label: {
                    Label("Apple Maps", systemImage: "map.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.0, green: 0.48, blue: 1.0))

                Button {
                    openInGoogleMaps()
                } label: {
                    Label("Google Maps", systemImage: "globe.americas.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
            }
        }
        .premiumCard()
    }

    private func openInAppleMaps() {
        guard let url = RouteNavigationService.appleMapsURL(
            origin: result.origin,
            destination: result.destination
        ) else { return }
        openURL(url)
    }

    private func openInGoogleMaps() {
        guard let url = RouteNavigationService.googleMapsURL(
            origin: result.origin,
            destination: result.destination
        ) else { return }
        openURL(url)
    }

    @ViewBuilder
    private func conditionsSection(_ conditions: RouteConditions) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Live Conditions")

            if conditions.weather.available {
                HStack(spacing: 12) {
                    Image(systemName: conditions.weather.systemImage)
                        .font(.title2)
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 40, height: 40)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(conditions.weather.condition)
                                .font(.subheadline.weight(.semibold))
                            severityChip(
                                label: conditions.weather.severityLabel,
                                severity: conditions.weather.severity
                            )
                        }
                        Text(weatherDetailText(conditions.weather))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            if conditions.road.available {
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "road.lanes")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 40, height: 40)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(conditions.road.dominantRoadLabel)
                            .font(.subheadline.weight(.semibold))
                        Text(roadDetailText(conditions.road))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            if conditions.road.constructionZones > 0 {
                conditionRow(
                    systemImage: "cone.fill",
                    color: .orange,
                    text: conditions.road.constructionZones == 1
                        ? "1 construction zone along the route"
                        : "\(conditions.road.constructionZones) construction zones along the route"
                )
            }

            if conditions.turns.available && conditions.turns.unprotectedLeftTurns > 0 {
                conditionRow(
                    systemImage: "arrow.turn.up.left",
                    color: AppDesign.safety,
                    text: conditions.turns.unprotectedLeftTurns == 1
                        ? "1 unprotected left turn (no signal)"
                        : "\(conditions.turns.unprotectedLeftTurns) unprotected left turns (no signal)"
                )
            }

            if !conditions.sources.isEmpty {
                Divider()
                Label("Inputs used: \(conditions.sources.map { sourceLabel($0) }.joined(separator: ", "))", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .premiumCard()
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "open-meteo": "Open-Meteo weather"
        case "osm-overpass": "OpenStreetMap road data"
        case "google-route-warnings": "Google route advisories"
        default: source
        }
    }

    private func conditionRow(systemImage: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }

    private func severityChip(label: String, severity: Double) -> some View {
        let color: Color = severity < 0.15 ? .green : severity < 0.4 ? .yellow : AppDesign.safety
        return Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func weatherDetailText(_ weather: WeatherConditions) -> String {
        var parts: [String] = [String(format: "%.0f°F", weather.temperatureF)]
        if weather.windGustMph >= 15 {
            parts.append(String(format: "gusts %.0f mph", weather.windGustMph))
        }
        if weather.visibilityMiles > 0 && weather.visibilityMiles < 5 {
            parts.append(String(format: "visibility %.1f mi", weather.visibilityMiles))
        }
        if weather.icyRisk > 0.3 {
            parts.append("ice risk")
        }
        return parts.joined(separator: " · ")
    }

    private func roadDetailText(_ road: RoadConditions) -> String {
        var parts: [String] = []
        if road.avgLanes > 0 {
            parts.append(String(format: "avg %.1f lanes", road.avgLanes))
        }
        if road.majorRoadShare > 0 {
            parts.append(String(format: "%.0f%% major roads", road.majorRoadShare * 100))
        }
        if road.narrowRoadShare >= 0.15 {
            parts.append(String(format: "%.0f%% narrow", road.narrowRoadShare * 100))
        }
        if road.unpavedShare >= 0.05 {
            parts.append(String(format: "%.0f%% unpaved", road.unpavedShare * 100))
        }
        return parts.isEmpty ? "Road data from OpenStreetMap" : parts.joined(separator: " · ")
    }

    private func hotspotsSection(_ hotspots: [SegmentHotspot]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Difficulty Hotspots")

            ForEach(Array(hotspots.prefix(5).enumerated()), id: \.element.id) { _, hotspot in
                HStack(spacing: 10) {
                    Text("#\(hotspot.segmentIndex + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.orange.gradient)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(hotspot.label ?? "Segment \(hotspot.segmentIndex + 1)")
                            .font(.subheadline.weight(.medium))
                        Text(String(format: "Intensity %.0f%%", hotspot.difficulty * 100))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .premiumCard()
    }

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Difficulty Breakdown")

            ForEach(selectedRoute.breakdown.items, id: \.key) { item in
                BreakdownBarRow(title: item.title, value: item.value)
            }
        }
        .premiumCard()
    }

    private func contributionsSection(_ contributions: [FactorContribution]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Top Factors")

            ForEach(contributions.prefix(5)) { entry in
                BreakdownBarRow(
                    title: entry.label,
                    value: entry.share
                )
            }
        }
        .premiumCard()
    }

    private var reasonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Why this score")

            if selectedRoute.reasons.isEmpty {
                Text("No specific difficulty factors identified for this route.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ReasonChipFlowLayout(reasons: selectedRoute.reasons)
            }
        }
        .premiumCard()
    }

    @ViewBuilder
    private var departureComparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Calmest departure",
                subtitle: "A local comparison of nearby departure times. Your recorded driving history stays on this iPhone."
            )

            if isComparingDepartures {
                HStack(spacing: 10) {
                    ProgressView().tint(AppDesign.accent)
                    Text("Comparing nearby departure times")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if let departureComparison {
                ForEach(departureComparison.candidates) { candidate in
                    DepartureComparisonRow(
                        candidate: candidate,
                        isCalmestAvailable: calmestDepartureID == candidate.id,
                        isCurrentDeparture: isCurrentDeparture(candidate),
                        isUpdating: isReanalyzingDeparture
                    ) {
                        reanalyze(at: candidate)
                    }
                }
                Label(
                    calmestDepartureID == nil
                        ? "Calmest available needs comparable traffic, after-dark, and weather data for every time."
                        : "Each time uses the best available route at that departure time.",
                    systemImage: "checkmark.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let departureComparisonError {
                Label("Departure comparison is unavailable right now. \(departureComparisonError)", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .premiumCard()
    }

    private var routeChoicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Route choices",
                subtitle: routeChoiceRanking?.comparisonLimitedByHistory == true
                    ? "Recorded history is still building, so choices are ordered by route difficulty."
                    : "Ranked by route demands and evidence recorded on this phone."
            )

            if let ranking = routeChoiceRanking {
                ForEach(ranking.choices) { choice in
                    AlternateRouteCard(
                        route: choice.route,
                        isSelected: choice.route.id == selectedRoute.id,
                        readinessHeadline: choice.assessment.headline,
                        badges: choice.badges,
                        comparisonLimitedByHistory: ranking.comparisonLimitedByHistory
                    ) {
                        selectRouteChoice(choice)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(AppDesign.accent)
                    Text("Preparing route choices")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .premiumCard()
    }

    private func isCurrentDeparture(_ candidate: DepartureComparisonCandidateResult) -> Bool {
        guard let date = candidate.departureDate else { return false }
        return abs(date.timeIntervalSince(result.departureTime)) < 1
    }

    @ViewBuilder
    private func detailTile(
        title: String,
        value: String,
        systemImage: String,
        valueColor: Color = .primary
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppDesign.accent)
            Text(value).font(AppDesign.Typography.metricValue).foregroundStyle(valueColor).monospacedDigit()
            Text(title).font(AppDesign.Typography.metricLabel).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PracticePlanPreview: View {
    let plan: PracticePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .foregroundStyle(AppDesign.safety)
                Text("Guided practice plan")
                    .font(.subheadline.weight(.semibold))
            }
            Text(plan.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(plan.goals) { goal in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: goal.requiresAdultSupervision ? "figure.and.child.holdinghands" : "checkmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(goal.requiresAdultSupervision ? AppDesign.safety : AppDesign.accent)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.title).font(.footnote.weight(.semibold))
                        Text(goal.coachingText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .background(AppDesign.safety.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppDesign.safety.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DepartureComparisonRow: View {
    let candidate: DepartureComparisonCandidateResult
    let isCalmestAvailable: Bool
    let isCurrentDeparture: Bool
    let isUpdating: Bool
    let action: () -> Void

    private var departureLabel: String {
        guard let date = candidate.departureDate else { return "Time unavailable" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        Group {
            if let route = candidate.route {
                Button(action: action) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: isCalmestAvailable ? "leaf.fill" : "clock")
                            .foregroundStyle(isCalmestAvailable ? AppDesign.positive : AppDesign.accent)
                            .frame(width: 28, height: 28)
                            .background((isCalmestAvailable ? AppDesign.positive : AppDesign.accent).opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(departureLabel).font(.subheadline.weight(.semibold))
                            Text("Difficulty \(route.formattedScoreWithUncertainty) · \(route.formattedDuration) · \(route.formattedDistance)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if isCalmestAvailable {
                                Text("Calmest available")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(AppDesign.positive)
                            } else if isCurrentDeparture {
                                Text("Current departure")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(AppDesign.accent)
                            } else if !DepartureComparisonRanking.hasComparableConditions(candidate) {
                                Text("Some comparison conditions are unavailable")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 0)
                        if isUpdating && !isCurrentDeparture {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: isCurrentDeparture ? "checkmark.circle.fill" : "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isCurrentDeparture ? AppDesign.accent : Color(.tertiaryLabel))
                        }
                    }
                    .padding(10)
                    .background(isCurrentDeparture ? AppDesign.accent.opacity(0.08) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableScaleStyle())
                .disabled(isCurrentDeparture || isUpdating)
                .accessibilityHint(isCurrentDeparture ? "This is the time used for the current route result." : "Refreshes the full route analysis for this departure time.")
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(departureLabel).font(.subheadline.weight(.semibold))
                        Text(candidate.error?.message ?? "This departure time was unavailable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct ReadinessHistorySummary: View {
    let profile: DriverReadinessProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Evidence from your saved drives", systemImage: "lock.shield.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(
                "\(profile.qualifyingDriveCount) qualifying \(profile.qualifyingDriveCount == 1 ? "drive" : "drives") · \(String(format: "%.1f", profile.reliableTraceMiles)) mi of validated GPS trace · \(profile.qualifyingDriveDayCount) \(profile.qualifyingDriveDayCount == 1 ? "day" : "days")"
            )
            .font(.footnote.weight(.medium))
            .monospacedDigit()

            VStack(alignment: .leading, spacing: 4) {
                readinessFact(
                    "8 PM–6 AM driving",
                    value: "\(String(format: "%.1f", profile.nightExposure.miles)) mi across \(profile.nightExposure.sessionCount) \(profile.nightExposure.sessionCount == 1 ? "drive" : "drives")",
                    symbol: "moon.stars.fill"
                )
                readinessFact(
                    "45+ mph baseline",
                    value: "\(String(format: "%.1f", profile.fastRoad45Exposure.miles)) mi across \(profile.fastRoad45Exposure.sessionCount) \(profile.fastRoad45Exposure.sessionCount == 1 ? "drive" : "drives")",
                    symbol: "speedometer"
                )
                readinessFact(
                    "Longest validated GPS trace",
                    value: durationText(profile.longestDriveDuration),
                    symbol: "clock.fill"
                )
            }

            Text("GPS, motion, and route overlap are analyzed on this iPhone only.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func readinessFact(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppDesign.accent)
                    .frame(width: 15)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 22)
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let minutes = max(0, Int((duration / 60).rounded()))
        return minutes >= 60
            ? "\(minutes / 60)h \(minutes % 60)m"
            : "\(minutes) min"
    }
}

private struct ReadinessInsightRow: View {
    let insight: DriverReadinessInsight

    private var color: Color {
        switch insight.state {
        case .matched:
            return AppDesign.positive
        case .practiceNeeded:
            return AppDesign.safety
        case .unmeasured:
            return AppDesign.accent
        case .informational:
            return .secondary
        }
    }

    private var symbol: String {
        switch insight.state {
        case .matched:
            return "checkmark.circle.fill"
        case .practiceNeeded:
            return "figure.and.child.holdinghands"
        case .unmeasured:
            return "questionmark.circle.fill"
        case .informational:
            return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(stateTitle)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(color)
                    .textCase(.uppercase)
                Text(insight.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let evidence = insight.evidence {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saved: \(evidence.recordedValue)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                        if let target = evidence.comparisonTarget {
                            Text("Compared with: \(target)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let collectionNote = evidence.collectionNote {
                            Label(collectionNote, systemImage: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var stateTitle: String {
        switch insight.state {
        case .matched: "Recorded"
        case .practiceNeeded: "Practice"
        case .unmeasured: "Not measured"
        case .informational: "Info"
        }
    }
}

private struct RouteDemandRow: View {
    let demand: RouteDemand

    private var color: Color {
        switch demand.level {
        case .low:
            return AppDesign.positive
        case .moderate:
            return AppDesign.safety
        case .high:
            return AppDesign.safety
        }
    }

    private var symbol: String {
        switch demand.kind {
        case .afterDark:
            return "moon.stars.fill"
        case .fastRoads:
            return "speedometer"
        case .merges:
            return "arrow.triangle.merge"
        case .complexIntersections:
            return "arrow.triangle.turn.up.right.diamond.fill"
        case .weatherVisibility:
            return "cloud.sun.rain.fill"
        case .sustainedDrive:
            return "clock.fill"
        case .traffic:
            return "car.2.fill"
        case .roadConditions:
            return "road.lanes"
        case nil:
            return "point.3.connected.trianglepath.dotted"
        }
    }

    private var levelLabel: String {
        switch demand.level {
        case .low: return "Low"
        case .moderate: return "Elevated"
        case .high: return "High"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(demand.title)
                            .font(.subheadline.weight(.semibold))
                        Text(levelLabel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(color.opacity(0.12), in: Capsule())
                    }
                    Text(demand.evidence)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * demand.intensity)
                }
            }
            .frame(height: 5)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

struct BreakdownBarRow: View {
    let title: String
    let value: Double

    @State private var displayedValue: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.0f%%", displayedValue * 100))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                    Capsule()
                        .fill(barColor)
                        .frame(width: geometry.size.width * min(max(displayedValue, 0), 1))
                }
            }
            .frame(height: 6)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : AppAnimation.reveal.delay(0.04)) {
                displayedValue = value
            }
        }
        .onChange(of: value) { _, newValue in
            withAnimation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.content) {
                displayedValue = newValue
            }
        }
    }

    private var barColor: Color {
        switch displayedValue {
        case 0..<0.35: return .green
        case 0.35..<0.65: return .orange
        default: return AppDesign.safety
        }
    }
}

// MARK: - Reason chips

struct ReasonChipView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Color(.tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous)
            )
    }
}

struct ReasonChipFlowLayout: View {
    let reasons: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(reasons.enumerated()), id: \.offset) { _, reason in
                ReasonChipView(text: reason)
            }
        }
    }
}

/// Simple wrapping layout for reason chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let intrinsicWidth = subviews.enumerated().reduce(CGFloat.zero) { partialWidth, item in
            let spacingBefore = item.offset == 0 ? 0 : spacing
            return partialWidth + spacingBefore + item.element.sizeThatFits(.unspecified).width
        }
        let proposedWidth = proposal.width ?? intrinsicWidth
        let maxWidth = max(0, proposedWidth.isFinite ? proposedWidth : intrinsicWidth)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let fittedSize = subview.sizeThatFits(
                ProposedViewSize(width: maxWidth, height: proposal.height)
            )
            let size = CGSize(width: min(fittedSize.width, maxWidth), height: fittedSize.height)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}

// MARK: - Map navigation
enum MapApp {
    case appleMaps
    case googleMaps
}

enum RouteNavigationService {
    static func appleMapsURL(origin: String, destination: String) -> URL? {
        url(
            scheme: "http",
            host: "maps.apple.com",
            path: "/",
            queryItems: [
                URLQueryItem(name: "saddr", value: origin),
                URLQueryItem(name: "daddr", value: destination),
                URLQueryItem(name: "dirflg", value: "d"),
            ]
        )
    }

    static func googleMapsAppURL(origin: String, destination: String) -> URL? {
        url(
            scheme: "comgooglemaps",
            host: nil,
            path: "/",
            queryItems: [
                URLQueryItem(name: "saddr", value: origin),
                URLQueryItem(name: "daddr", value: destination),
                URLQueryItem(name: "directionsmode", value: "driving"),
            ]
        )
    }

    static func googleMapsWebURL(origin: String, destination: String) -> URL? {
        url(
            scheme: "https",
            host: "www.google.com",
            path: "/maps/dir/",
            queryItems: [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: "origin", value: origin),
                URLQueryItem(name: "destination", value: destination),
                URLQueryItem(name: "travelmode", value: "driving"),
            ]
        )
    }

    static func googleMapsURL(origin: String, destination: String) -> URL? {
        if let appURL = googleMapsAppURL(origin: origin, destination: destination),
           UIApplication.shared.canOpenURL(appURL) {
            return appURL
        }
        return googleMapsWebURL(origin: origin, destination: destination)
    }

    static var isGoogleMapsInstalled: Bool {
        guard let url = URL(string: "comgooglemaps://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    private static func url(
        scheme: String,
        host: String?,
        path: String,
        queryItems: [URLQueryItem]
    ) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.queryItems = queryItems
        return components.url
    }
}

#Preview {
    NavigationStack {
        ResultsView(
            result: RouteAnalysisResult(
                origin: "Miami, FL",
                destination: "Orlando, FL",
                departureTime: Date().addingTimeInterval(15 * 60),
                primaryRoute: ScoredRoute(
                    score: 4.2,
                    uncalibratedScore: 4.0,
                    label: .moderate,
                    reasons: ["Mostly highway", "Light traffic"],
                    breakdown: DifficultyBreakdown(
                        speed: 0.30, merges: 0.15, turns: 0.35, traffic: 0.15,
                        length: 0.45, fatigue: 0.20, weather: 0.35, road: 0.15,
                        highway: 0.30, maneuvers: 0.35, navDensity: 0.20, effort: 0.45
                    ),
                    contributions: [
                        FactorContribution(
                            factor: "speed",
                            label: "High-speed road burden",
                            value: 0.30,
                            weight: 0.24,
                            contribution: 0.072,
                            share: 0.35
                        ),
                        FactorContribution(
                            factor: "length",
                            label: "Length/monotony burden",
                            value: 0.45,
                            weight: 0.14,
                            contribution: 0.063,
                            share: 0.26
                        )
                    ],
                    uncertainty: ScoreUncertainty(low: 3.6, high: 4.8, confidence: 0.75, spread: 1.2),
                    hotspots: [],
                    conditions: RouteConditions(
                        weather: WeatherConditions(
                            available: true, condition: "Rain", severity: 0.45,
                            precipIntensity: 0.5, snowRisk: 0, windSeverity: 0.2,
                            lowVisibilityRisk: 0.1, icyRisk: 0, temperatureF: 54,
                            windGustMph: 22, visibilityMiles: 4.5
                        ),
                        road: RoadConditions(
                            available: true, avgLanes: 2.6, narrowRoadShare: 0.1,
                            majorRoadShare: 0.8, unpavedShare: 0, roadSizeScore: 0.2,
                            constructionZones: 1, dominantRoadClass: "motorway"
                        ),
                        turns: TurnExposure(
                            available: true, unprotectedLeftTurns: 2,
                            protectedLeftTurns: 3, unprotectedTurnShare: 0.4
                        ),
                        sources: ["open-meteo", "osm-overpass"]
                    ),
                    modelVersion: "hybrid-v5",
                    distanceMeters: 312000,
                    durationSeconds: 10800,
                    staticDurationSeconds: 9900,
                    trafficDelaySeconds: 900,
                    polyline: "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
                    bounds: RouteBounds(
                        southwest: Coordinate(latitude: 30.2, longitude: -97.8),
                        northeast: Coordinate(latitude: 32.8, longitude: -96.8)
                    ),
                    scoreDelta: nil,
                    routeDemands: [
                        RouteDemand(
                            id: "afterDark",
                            intensity: 0.85,
                            level: .high,
                            evidence: "Most of the drive falls in the 8 PM–6 AM window.",
                            available: true
                        ),
                        RouteDemand(
                            id: "fastRoads",
                            intensity: 0.68,
                            level: .high,
                            evidence: "72% of the route is estimated at 45+ mph.",
                            available: true
                        ),
                        RouteDemand(
                            id: "merges",
                            intensity: 0.56,
                            level: .moderate,
                            evidence: "2 ramps or merge transitions appear in the route instructions.",
                            available: true
                        )
                    ]
                ),
                alternateRoutes: []
            )
        )
    }
    .environmentObject(DriveSessionManager())
}
