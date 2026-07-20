import SwiftUI
import UIKit

struct HomeView: View {
    @ObservedObject var form: RoutePlanningFormModel
    @State private var isLoading = false
    @State private var isCompletingLoading = false
    @State private var pendingResult: RouteAnalysisResult?
    @State private var errorMessage: String?
    @State private var navigationPath = NavigationPath()
    @State private var mapPreview: RoutePlanningMapSummary?
    @StateObject private var locationCoordinator = RoutePlanningLocationCoordinator()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let apiClient = APIClient()

    private var planningStage: RoutePlanningStage {
        RoutePlanningStage(origin: form.origin, destination: form.destination)
    }

    private var canEnterDestination: Bool {
        planningStage != .chooseOrigin
    }

    /// Current-location selection is already a deliberate choice, even while
    /// MapKit is still resolving its human-readable address. Reveal the next
    /// field at that moment, but keep Analyze disabled until the origin is
    /// actually confirmed.
    private var destinationIsRevealed: Bool {
        guard !canEnterDestination else { return true }
        if !form.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        guard form.usesCurrentLocation else { return false }
        if case .locating = locationCoordinator.state {
            return true
        }
        return false
    }

    private var canAnalyze: Bool {
        planningStage == .readyToAnalyze && !isLoading
    }

    /// A shared Maps route may prefer the current location when no explicit
    /// origin is supplied. That preference is not consent to expose the blue
    /// dot. MapKit gets location access only after the person taps the visible
    /// current-location control and the coordinator begins resolving it.
    private var shouldShowCurrentLocationOnMap: Bool {
        guard form.usesCurrentLocation else { return false }
        switch locationCoordinator.state {
        case .locating, .resolved:
            return true
        case .awaitingOrigin, .manualEntry:
            return false
        }
    }

    private var progressiveReveal: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                routeBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        headerSection

                        if let notice = form.importNotice {
                            importNoticeBanner(notice)
                                .transition(progressiveReveal)
                        }

                        routeCard

                        mapPreviewSection

                        departureContainer

                        if let errorMessage {
                            errorBanner(errorMessage)
                                .transition(.opacity)
                        }

                        analyzeButton
                        routeChecksSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }

                if isLoading {
                    RouteAnalysisLoadingView(isFinishing: isCompletingLoading) { completeLoading() }
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: RouteAnalysisResult.self) { ResultsView(result: $0) }
            .onChange(of: locationCoordinator.state) { _, state in
                switch state {
                case .resolved(let address) where form.usesCurrentLocation:
                    form.origin = address
                case .manualEntry where form.usesCurrentLocation:
                    withAnimation(reduceMotion ? .easeOut(duration: 0.18) : AppAnimation.selection) {
                        form.usesCurrentLocation = false
                    }
                default:
                    break
                }
            }
            .onChange(of: form.importedRouteID) { _, importedRouteID in
                guard importedRouteID != nil else { return }
                navigationPath = NavigationPath()
                mapPreview = nil
            }
        }
        .preferredColorScheme(.dark)
    }

    private var routeBackground: Color {
        Color(red: 0.045, green: 0.045, blue: 0.05)
    }

    private var routeSurface: Color {
        Color.white.opacity(reduceTransparency ? 0.12 : 0.075)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            BrandWordmark()

            HStack(alignment: .center, spacing: 16) {
                Text("Plan your route")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.09), in: Circle())
                    .accessibilityHidden(true)
            }

            Text("Set your start, then see the road before you take it.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private var routeCard: some View {
        VStack(spacing: 0) {
            originRow

            if destinationIsRevealed {
                Divider()
                    .overlay(.white.opacity(0.1))
                    .padding(.leading, 68)
                    .transition(.opacity)

                destinationRow
                    .transition(progressiveReveal)
            }
        }
        .padding(.vertical, 6)
        .background(routeSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.18) : AppAnimation.selection, value: destinationIsRevealed)
    }

    @ViewBuilder
    private var originRow: some View {
        if form.usesCurrentLocation {
            HStack(alignment: .center, spacing: 14) {
                RoutePlanningFieldIcon(symbol: "location.circle.fill", tint: .white)

                Button {
                    locationCoordinator.useCurrentLocation()
                } label: {
                    routeFieldCopy(
                        label: "FROM",
                        value: currentLocationTitle,
                        valueColor: .white.opacity(0.94)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Starting location")
                .accessibilityValue(currentLocationTitle)
                .accessibilityHint("Double tap to refresh your current location")

                if case .locating = locationCoordinator.state {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }

                Button(action: switchToManualOrigin) {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(PressableScaleStyle())
                .accessibilityLabel("Enter a different starting location")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 17)
        } else {
            HStack(alignment: .top, spacing: 14) {
                RoutePlanningFieldIcon(symbol: "circle.inset.filled", tint: AppDesign.accent)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 4) {
                    routeFieldLabel("FROM")
                    AddressSearchField(
                        title: "Starting location",
                        placeholder: "Enter starting location",
                        systemImage: "circle.fill",
                        iconColor: AppDesign.accent,
                        showsIcon: false,
                        text: $form.origin
                    )
                    .layoutPriority(1)

                    if case .manualEntry(let message) = locationCoordinator.state,
                       let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }

                Button(action: chooseCurrentLocation) {
                    Image(systemName: "location.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(PressableScaleStyle())
                .padding(.top, 8)
                .accessibilityLabel("Use current location")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
        }
    }

    private var destinationRow: some View {
        HStack(alignment: .top, spacing: 14) {
            RoutePlanningFieldIcon(symbol: "mappin.circle.fill", tint: .white.opacity(0.82))
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 4) {
                routeFieldLabel("TO")
                AddressSearchField(
                    title: "Destination",
                    placeholder: "Where are you headed?",
                    systemImage: "mappin",
                    iconColor: .white.opacity(0.82),
                    showsIcon: false,
                    text: $form.destination
                )
                .layoutPriority(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .accessibilityElement(children: .contain)
    }

    private func routeFieldCopy(label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            routeFieldLabel(label)
            Text(value)
                .font(.headline.weight(.medium))
                .foregroundStyle(valueColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func routeFieldLabel(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(.white.opacity(0.4))
    }

    private var currentLocationTitle: String {
        switch locationCoordinator.state {
        case .locating:
            "Finding current location"
        case .resolved(let address):
            address
        case .manualEntry(let message):
            message ?? "Current location unavailable"
        case .awaitingOrigin:
            form.origin.isEmpty ? "Current location" : form.origin
        }
    }

    private var mapPreviewSection: some View {
        ZStack(alignment: .bottomLeading) {
            RoutePlanningMapPreview(
                origin: form.origin,
                destination: form.destination,
                usesCurrentLocation: form.usesCurrentLocation,
                showsCurrentLocation: shouldShowCurrentLocationOnMap,
                summary: $mapPreview
            )
            .allowsHitTesting(false)

            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            HStack(spacing: 8) {
                Image(systemName: mapPreview == nil ? "map.fill" : "arrow.triangle.turn.up.right.diamond.fill")
                    .foregroundStyle(.white.opacity(0.86))
                Text(mapPreview?.displayText ?? mapPlaceholderText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.72), in: Capsule(style: .continuous))
            .padding(14)
            .accessibilityElement(children: .combine)
        }
        .frame(height: 248)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
        .accessibilityLabel(mapPreview?.accessibilityLabel ?? mapPlaceholderText)
    }

    private var mapPlaceholderText: String {
        switch planningStage {
        case .chooseOrigin:
            "Apple Maps preview"
        case .chooseDestination:
            "Add a destination to preview your route"
        case .readyToAnalyze:
            "Preparing Apple Maps preview"
        }
    }

    private var departureSection: some View {
        HStack(spacing: 14) {
            Image(systemName: "clock.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppDesign.accent)
                .frame(width: 38, height: 38)
                .background(AppDesign.accent.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Departure")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Traffic estimates use this time")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer(minLength: 8)

            DatePicker(
                "Departure time",
                selection: $form.departureTime,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(AppDesign.accent)
            .colorScheme(.dark)
        }
        .padding(16)
        .background(routeSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var departureContainer: some View {
        Group {
            if planningStage == .readyToAnalyze {
                departureSection
                    .transition(progressiveReveal)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.18) : AppAnimation.selection, value: planningStage)
    }

    private var analyzeButton: some View {
        Button {
            Task { await analyzeRoute() }
        } label: {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(isLoading ? "Analyzing route" : analyzeButtonTitle)
                    .font(.headline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(canAnalyze ? .black : .white.opacity(0.45))
            .background(
                canAnalyze ? Color.white : Color.white.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
        .buttonStyle(PressableScaleStyle())
        .disabled(!canAnalyze)
        .animation(AppAnimation.quick, value: canAnalyze)
        .animation(AppAnimation.quick, value: isLoading)
        .accessibilityHint(canAnalyze ? "Analyzes road conditions and route difficulty" : "Complete your start and destination first")
    }

    private var analyzeButtonTitle: String {
        switch planningStage {
        case .chooseOrigin:
            "Choose a starting point"
        case .chooseDestination:
            "Choose a destination"
        case .readyToAnalyze:
            "Analyze difficulty"
        }
    }

    private var routeChecksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What Swerve checks")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                RouteCheckPill(symbol: "car.2.fill", title: "Traffic")
                RouteCheckPill(symbol: "arrow.triangle.merge", title: "Merges")
                RouteCheckPill(symbol: "cloud.sun.rain.fill", title: "Conditions")
            }

            Text("Route analysis combines road geometry with available traffic and weather data. Missing signals are left out, never guessed.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func importNoticeBanner(_ notice: RouteImportNotice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "arrow.down.doc.fill")
                .foregroundStyle(notice.isError ? .orange : AppDesign.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(notice.message)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                form.clearImportNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(PressableScaleStyle())
            .accessibilityLabel("Dismiss imported route notice")
        }
        .padding(14)
        .background(routeSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke((notice.isError ? Color.orange : AppDesign.accent).opacity(0.26), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(notice.title). \(notice.message)")
    }

    private func switchToManualOrigin() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : AppAnimation.selection) {
            form.usesCurrentLocation = false
            form.origin = ""
            locationCoordinator.useManualEntry()
        }
    }

    private func chooseCurrentLocation() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : AppAnimation.selection) {
            form.usesCurrentLocation = true
            form.origin = ""
        }
        locationCoordinator.useCurrentLocation()
    }

    private func analyzeRoute() async {
        withAnimation(AppAnimation.quick) { errorMessage = nil }
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : AppAnimation.quick) {
            isLoading = true
        }
        do {
            let response = try await apiClient.analyzeRoute(
                origin: form.origin,
                destination: form.destination,
                departureTime: form.departureTime,
                includeAlternates: true
            )
            pendingResult = RouteAnalysisResult(
                origin: form.origin,
                destination: form.destination,
                departureTime: form.departureTime,
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

private struct RoutePlanningFieldIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 44)
            .accessibilityHidden(true)
    }
}

private struct RouteCheckPill: View {
    let symbol: String
    let title: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(.white.opacity(0.075), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.055), lineWidth: 1)
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

#Preview {
    HomeView(form: RoutePlanningFormModel())
}
