import SwiftUI

struct HomeView: View {
    @State private var origin = ""
    @State private var destination = ""
    @State private var departureTime = Date().addingTimeInterval(15 * 60)
    @State private var isLoading = false
    @State private var isCompletingLoading = false
    @State private var pendingResult: RouteAnalysisResult?
    @State private var errorMessage: String?
    @State private var navigationPath = NavigationPath()

    private let apiClient = APIClient()

    private var canAnalyze: Bool {
        !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isLoading
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                        headerSection

                        routeCard

                        departureCard

                        if let errorMessage {
                            errorBanner(errorMessage)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        PrimaryActionButton(
                            title: "Analyze Difficulty",
                            isLoading: isLoading,
                            isEnabled: canAnalyze
                        ) {
                            Task { await analyzeRoute() }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, AppDesign.contentPadding)
                    .padding(.vertical, 12)
                }
                .background(Color(.systemGroupedBackground))
                .animation(AppAnimation.quick, value: errorMessage)

                if isLoading {
                    RouteAnalysisLoadingView(isFinishing: isCompletingLoading) {
                        completeLoading()
                    }
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .navigationTitle("Swerve")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: RouteAnalysisResult.self) { result in
                ResultsView(result: result)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Plan your drive")
                .font(AppDesign.Typography.heroTitle)
                .tracking(-0.5)
            Text("Compare route difficulty before you leave.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Route")

            VStack(spacing: 0) {
                AddressSearchField(
                    title: "Origin",
                    placeholder: "Starting address",
                    systemImage: "circle.fill",
                    iconColor: .green,
                    text: $origin
                )

                Divider()
                    .padding(.leading, 32)
                    .padding(.vertical, 4)

                AddressSearchField(
                    title: "Destination",
                    placeholder: "Destination address",
                    systemImage: "flag.fill",
                    iconColor: .red,
                    text: $destination
                )
            }
        }
        .premiumCard()
    }

    private var departureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Departure",
                subtitle: "Traffic estimates use your departure time."
            )

            DatePicker(
                "When",
                selection: $departureTime,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
        }
        .premiumCard()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
    }

    private func analyzeRoute() async {
        withAnimation(AppAnimation.quick) {
            errorMessage = nil
        }
        isLoading = true

        do {
            let response = try await apiClient.analyzeRoute(
                origin: origin,
                destination: destination,
                departureTime: departureTime,
                includeAlternates: true
            )

            let result = RouteAnalysisResult(
                origin: origin,
                destination: destination,
                primaryRoute: response.primaryRoute,
                alternateRoutes: response.alternateRoutes
            )

            pendingResult = result
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isCompletingLoading = true
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(AppAnimation.quick) {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func completeLoading() {
        guard let pendingResult else { return }
        isCompletingLoading = false
        isLoading = false
        self.pendingResult = nil
        navigationPath.append(pendingResult)
    }
}

struct RouteAnalysisResult: Hashable {
    let origin: String
    let destination: String
    let primaryRoute: ScoredRoute
    let alternateRoutes: [ScoredRoute]
}

#Preview {
    HomeView()
}
