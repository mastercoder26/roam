import SwiftUI
import UIKit
import ClerkKitUI

struct HomeView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var authSession: AuthSessionStore
    @ObservedObject private var recentRoutes = RecentRouteStore.shared
    @ObservedObject var form: RoutePlanningFormModel
    @ObservedObject var analysis: RoutePlanningAnalysisModel
    @State private var isVisible = false

    private var isLoading: Bool { analysis.isLoading }
    private var isCompletingLoading: Bool { analysis.result != nil }
    private var errorMessage: String? { analysis.errorMessage }
    @State private var navigationPath = NavigationPath()
    @State private var mapPreview: RoutePlanningMapSummary?
    @State private var showingHowRoamWorks = false
    @State private var authIsPresented = false
    @State private var showingRecentRoutes = false
    @State private var showingDeparturePicker = false
    @State private var planningContentHeight: CGFloat = 330
    @State private var availableHeight: CGFloat = 700
    @State private var isEditingOrigin = false
    @State private var isEditingDestination = false

    private var isEditingRoute: Bool { isEditingOrigin || isEditingDestination }
    @StateObject private var locationCoordinator = RoutePlanningLocationCoordinator()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    private var formPresentation: RoutePlanningFormPresentation {
        RoutePlanningFormPresentation(
            origin: form.origin,
            destination: form.destination,
            usesCurrentLocation: form.usesCurrentLocation
        )
    }

    private var planningStage: RoutePlanningStage {
        formPresentation.stage
    }

    private var primaryAction: RoutePlanningPrimaryAction {
        RoutePlanningPrimaryAction(
            stage: planningStage,
            isSignedIn: authSession.isSignedIn,
            isAccountRestoring: isAccountRestoring,
            isLoading: isLoading
        )
    }

    private var isAccountRestoring: Bool {
        switch authSession.state {
        case .restoring, .authenticating: true
        case .signedOut, .signedIn, .signedInOffline: false
        }
    }

    private var canSwapEndpoints: Bool {
        !form.usesCurrentLocation &&
            !form.origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !form.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isLoading
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
            ZStack(alignment: .bottom) {
                RoutePlanningMapPreview(
                    origin: form.origin,
                    destination: form.destination,
                    usesCurrentLocation: form.usesCurrentLocation,
                    showsCurrentLocation: shouldShowCurrentLocationOnMap,
                    summary: $mapPreview
                )
                .ignoresSafeArea(.container)
                .accessibilityIdentifier("routes.backgroundMap")

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        ScreenHeader(title: "Routes")
                        Spacer()
                        if !recentRoutes.entries.isEmpty {
                            Button { showingRecentRoutes = true } label: {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                            .accessibilityLabel("Recent routes")
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .controlSize(.large)
                        }
                        Button { showingHowRoamWorks = true } label: {
                            Image(systemName: "info.circle")
                        }
                        .accessibilityIdentifier("routes.howRoamWorks")
                        .accessibilityLabel("How Roam works")
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                    }
                    .padding(.horizontal, AppDesign.contentPadding)
                    .padding(.top, AppDesign.screenTopPadding)
                    .background(alignment: .top) {
                        LinearGradient(colors: [AppDesign.canvas.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: .top)
                            .padding(.bottom, -36)
                    }
                    Spacer(minLength: 16)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Where to?")
                                .font(.system(.title, weight: .semibold))
                            if let notice = form.importNotice { importNoticeBanner(notice) }
                            routeCard
                            if !isEditingRoute {
                                departureContainer
                                if let errorMessage { errorBanner(errorMessage) }
                                analyzeButton
                            }
                        }
                        .padding(20)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { planningContentHeight = $0 }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDismissesKeyboard(.interactively)
                    .frame(height: min(planningContentHeight, max(160, availableHeight - 112)))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(AppDesign.glassHighlight.opacity(0.45), lineWidth: 0.5)
                    }
                    .shadow(color: AppDesign.cardShadow.opacity(0.35), radius: 18, y: 8)
                    .padding(.horizontal, 16)
                    .padding(.bottom, isEditingRoute ? 12 : 18)
                    .accessibilityIdentifier("routes.planningSheet")
                    .disabled(isLoading)
                }
                if isLoading {
                    RouteAnalysisLoadingView(
                        isFinishing: isCompletingLoading,
                        coordinates: mapPreview?.coordinates ?? [],
                        destination: form.destination,
                        routeSummary: mapPreview?.displayText,
                        onCancel: { analysis.cancel() },
                        onDepartureComplete: { completeLoading() }
                    )
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { availableHeight = $0 }
            .toolbar(isEditingRoute ? .hidden : .visible, for: .tabBar)
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
                analysis.cancel()
                navigationPath = NavigationPath()
                mapPreview = nil
            }
        }
        .onAppear {
            isVisible = true
            completeLoading()
        }
        .onDisappear { isVisible = false }
        .sheet(isPresented: $showingDeparturePicker) {
            NavigationStack {
                DatePicker("Departure time", selection: $form.departureTime, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .padding(20)
                    .navigationTitle("Departure time")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingDeparturePicker = false }
                    } }
            }.presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingRecentRoutes) {
            NavigationStack {
                ScrollView { recentRoutesSection.padding(20) }
                    .navigationTitle("Recent routes")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingRecentRoutes = false }
                    } }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingHowRoamWorks) {
            HowRoamWorksSheet()
        }
        .sheet(isPresented: $authIsPresented) {
            AuthView()
        }
        .onChange(of: authSession.state) { _, state in
            switch state {
            case .signedIn, .signedInOffline:
                authIsPresented = false
            case .restoring, .signedOut, .authenticating:
                break
            }
        }
    }

    private var routeCard: some View {
        VStack(spacing: 0) {
            originRow

            Group {
                Divider()
                    .overlay(AppDesign.Ink.tertiary.opacity(0.4))
                    .padding(.leading, 68)

                destinationRow
            }
        }
        .padding(.vertical, AppDesign.space8)

        .overlay(alignment: .trailing) {
            if canSwapEndpoints {
                Button(action: swapEndpoints) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppDesign.Ink.primary)
                        .frame(width: 36, height: 36)
                        .background(AppDesign.cardSurfaceElevated, in: Circle())
                        .overlay {
                            Circle().stroke(AppDesign.cardStrokeStrong, lineWidth: 0.75)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableScaleStyle())
                .padding(.trailing, 10)
                .transition(progressiveReveal)
                .accessibilityLabel("Swap starting location and destination")
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.selection, value: canSwapEndpoints)
    }

    private func swapEndpoints() {
        guard canSwapEndpoints else { return }
        let previousOrigin = form.origin
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.selection) {
            form.origin = form.destination
            form.destination = previousOrigin
            mapPreview = nil
        }
    }

    @ViewBuilder
    private var originRow: some View {
        if form.usesCurrentLocation {
            VStack(alignment: .leading, spacing: AppDesign.space8) {
                HStack(alignment: .center, spacing: 14) {
                    RoutePlanningFieldIcon(symbol: "location.fill", tint: AppDesign.Ink.primary)

                    Button {
                        locationCoordinator.useCurrentLocation()
                    } label: {
                        routeFieldCopy(
                            label: "FROM",
                            value: currentLocationTitle,
                            valueColor: AppDesign.Ink.primary
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Starting location")
                    .accessibilityValue(currentLocationTitle)
                    .accessibilityHint("Double tap to refresh your current location")

                    if case .locating = locationCoordinator.state {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppDesign.Ink.primary)
                    }

                    Button(action: switchToManualOrigin) {
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppDesign.Ink.primary.opacity(0.88))
                            .frame(width: 36, height: 36)
                            .background(AppDesign.Ink.primary.opacity(0.14), in: Circle())
                            // Keeps the visible chip at its designed 36pt while
                            // still meeting the 44pt minimum tap target.
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableScaleStyle())
                    .accessibilityLabel("Enter a different starting location")
                }

                // A coarse fix is used rather than left spinning, but it is
                // never presented as an exact address.
                if let accuracyNotice = locationCoordinator.accuracyNotice {
                    Text(accuracyNotice)
                        .font(.caption)
                        .foregroundStyle(AppDesign.safety.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 50)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 0)
            .padding(.vertical, 10)
        } else {
            HStack(alignment: .top, spacing: 14) {
                RoutePlanningFieldIcon(symbol: "circle.inset.filled", tint: AppDesign.accent)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: AppDesign.space4) {
                    routeFieldLabel("FROM")
                    AddressSearchField(
                        title: "Starting location",
                        placeholder: "Enter a starting location",
                        systemImage: "circle.fill",
                        iconColor: AppDesign.accent,
                        showsIcon: false,
                        text: $form.origin,
                        onFocusChanged: { isEditingOrigin = $0 }
                    )
                    .layoutPriority(1)

                    if case .manualEntry(let message) = locationCoordinator.state,
                       let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(AppDesign.safety.opacity(0.95))
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }

                Button(action: chooseCurrentLocation) {
                    Image(systemName: "location.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppDesign.Ink.primary.opacity(0.88))
                        .frame(width: 36, height: 36)
                        .background(AppDesign.Ink.primary.opacity(0.14), in: Circle())
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableScaleStyle())
                .padding(.top, 8)
                .accessibilityLabel("Use current location")
            }
            .padding(.horizontal, 0)
            .padding(.vertical, 10)
        }
    }

    private var destinationRow: some View {
        HStack(alignment: .top, spacing: 14) {
            RoutePlanningFieldIcon(symbol: "mappin.and.ellipse", tint: AppDesign.Ink.secondary)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: AppDesign.space4) {
                routeFieldLabel("TO")
                AddressSearchField(
                    title: "Destination",
                    placeholder: "Enter a destination",
                    systemImage: "mappin",
                    iconColor: AppDesign.Ink.secondary,
                    showsIcon: false,
                    text: $form.destination,
                    onFocusChanged: { isEditingDestination = $0 }
                )
                .layoutPriority(1)
            }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func routeFieldCopy(label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.space4) {
            routeFieldLabel(label)
            Text(value)
                .font(AppDesign.Typography.bodyEmphasized)
                .foregroundStyle(valueColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func routeFieldLabel(_ value: String) -> some View {
        Text(value.capitalized)
            .font(.caption.weight(.medium))
            .foregroundStyle(AppDesign.Ink.label)
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

    private var recentRoutesSection: some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            RailHeader(title: "Recent routes") {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.quick) {
                        recentRoutes.clear()
                    }
                } label: {
                    Text("Clear")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppDesign.Ink.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear recent routes")
            }

            VStack(spacing: AppDesign.space8) {
                ForEach(recentRoutes.entries) { entry in
                    RecentRouteRow(entry: entry) {
                        applyRecentRoute(entry)
                    }
                }
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.content, value: recentRoutes.entries)
    }

    private func applyRecentRoute(_ entry: RecentRouteEntry) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : AppAnimation.selection) {
            form.usesCurrentLocation = false
            form.origin = entry.origin
            form.destination = entry.destination
            showingRecentRoutes = false
        }
    }

    private var departureContainer: some View {
        Menu {
            Button("Leave now") { form.departureTime = Date() }
            Button("Choose departure time") { showingDeparturePicker = true }
        } label: {
            Label(abs(form.departureTime.timeIntervalSinceNow) < 90 ? "Leave now" : form.departureTime.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                .font(.footnote)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(AppDesign.Ink.primary)
        .accessibilityLabel("Departure time")
    }

    private var analyzeButton: some View {
        Button {
            switch primaryAction {
            case .signIn:
                authIsPresented = true
            case .analyze:
                withAnimation(loadingTransitionAnimation) {
                    analysis.start(form: form, auth: authSession, recentRoutes: recentRoutes)
                }
            case .chooseOrigin, .chooseDestination, .waitingForAccount, .analyzing:
                break
            }
        } label: {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(AppDesign.Ink.tertiary)
                } else if primaryAction == .signIn {
                    Image(systemName: primaryActionSymbol)
                }
                Text(primaryActionTitle)
                    .font(.headline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(primaryAction.isEnabled ? AppDesign.primarySurfaceForeground : AppDesign.Ink.tertiary)
            .background(
                primaryAction.isEnabled ? AppDesign.Ink.primary : AppDesign.Ink.primary.opacity(0.10),
                in: Capsule()
            )
            .shadow(color: primaryAction.isEnabled ? AppDesign.cardShadow.opacity(0.5) : .clear, radius: 16, y: 7)
        }
        .buttonStyle(PressableScaleStyle())
        .disabled(!primaryAction.isEnabled)
        .animation(AppAnimation.quick, value: primaryAction)
        .animation(AppAnimation.quick, value: isLoading)
        .accessibilityHint(primaryActionAccessibilityHint)
    }

    private var primaryActionTitle: String {
        switch primaryAction {
        case .chooseOrigin:
            "Choose a starting location"
        case .chooseDestination:
            "Choose a destination"
        case .waitingForAccount:
            "Preparing your account"
        case .signIn:
            "Sign in to check route"
        case .analyze:
            "Check route"
        case .analyzing:
            "Analyzing route"
        }
    }

    private var primaryActionSymbol: String {
        switch primaryAction {
        case .signIn: "person.crop.circle.badge.plus"
        case .waitingForAccount: "person.crop.circle"
        case .chooseOrigin, .chooseDestination, .analyze, .analyzing: "point.topleft.down.to.point.bottomright.curvepath"
        }
    }

    private var primaryActionAccessibilityHint: String {
        switch primaryAction {
        case .signIn:
            "Opens sign in and keeps this route ready"
        case .analyze:
            "Analyzes road conditions and route difficulty"
        case .waitingForAccount:
            "Waits for your existing sign-in session"
        case .chooseOrigin, .chooseDestination:
            "Complete your start and destination first"
        case .analyzing:
            "Route analysis is in progress"
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppDesign.safety)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppDesign.Ink.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            AppDesign.safety.opacity(0.12),
            in: RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
        )
        .elevation(AppDesign.Elevation.low)
    }

    private func importNoticeBanner(_ notice: RouteImportNotice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "arrow.down.doc.fill")
                .foregroundStyle(notice.isError ? AppDesign.safety : AppDesign.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppDesign.Ink.primary)
                Text(notice.message)
                    .font(.footnote)
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                form.clearImportNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .frame(width: 28, height: 28)
                    .background(AppDesign.Ink.primary.opacity(0.10), in: Circle())
            }
            .buttonStyle(PressableScaleStyle())
            .accessibilityLabel("Dismiss imported route notice")
        }
        .padding(14)
        .background(AppDesign.cardSurface, in: RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
                .stroke((notice.isError ? AppDesign.safety : AppDesign.accent).opacity(0.28), lineWidth: 1)
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

    private func completeLoading() {
        guard isVisible else { return }
        withAnimation(loadingTransitionAnimation) {
            if let result = analysis.takeResult() {
                navigationPath.append(result)
            }
        }
    }

    private var loadingTransitionAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: PremiumMotionSpec.reducedFocusTransition.duration)
            : AppAnimation.focus
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


#Preview {
    HomeView(form: RoutePlanningFormModel(), analysis: RoutePlanningAnalysisModel())
}
