import SwiftUI

struct DriveView: View {
    @EnvironmentObject private var session: DriveSessionManager
    @State private var showingHelp = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                    header
                    if session.queuedPracticeRoute != nil, !session.isRecording {
                        practiceRouteReadyCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    recordingCard
                    liveMetrics

                    if let score = session.lastScore, !session.isRecording {
                        DriveScoreCard(score: score)
                    } else {
                        howItWorksCard
                    }

                    if !session.recordedDrives.isEmpty, !session.isRecording {
                        driveHistory
                    }
                }
                .padding(.horizontal, AppDesign.contentPadding)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Drive")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingHelp = true
                    } label: {
                        Label("Get help", systemImage: "lifepreserver.fill")
                    }
                    .accessibilityHint("Shows safety and emergency options")
                }
            }
        }
        .sheet(isPresented: $showingHelp) {
            DriveHelpSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.isRecording ? "Stay focused on the road" : "Practice with purpose")
                .font(AppDesign.Typography.heroTitle)
                .tracking(-0.5)
            Text(session.isRecording
                 ? "Swerve is quietly tracking motion and location."
                 : "Start and end each drive yourself. Your raw readings stay on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var practiceRouteReadyCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppDesign.accent)
                .frame(width: 34, height: 34)
                .background(AppDesign.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Practice route ready")
                    .font(.subheadline.weight(.semibold))
                Text("Start manually when you’re ready. Swerve only counts this as route practice when saved GPS overlaps the route.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                session.clearPlannedPracticeRoute()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(PressableScaleStyle())
            .accessibilityLabel("Cancel practice route")
            .accessibilityHint("Removes this planned route from the next drive")
        }
        .padding(14)
        .background(AppDesign.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
                .stroke(AppDesign.accent.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Practice route ready")
    }

    private var recordingCard: some View {
        VStack(spacing: 18) {
            Label(session.isRecording ? "DRIVE IN PROGRESS" : "MANUAL DRIVE", systemImage: session.isRecording ? "record.circle.fill" : "steeringwheel")
                .font(.caption.weight(.bold))
                .foregroundStyle(session.isRecording ? .red : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            FlipClock(elapsed: session.elapsed, isActive: session.isRecording)

            Button {
                if session.isRecording { session.endDrive() } else { session.startDrive() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: session.isRecording ? "stop.fill" : "record.circle")
                    Text(session.isRecording ? "End drive" : "Start drive")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
                        .fill(session.isRecording ? Color.red : Color.accentColor)
                )
            }
            .buttonStyle(PressableScaleStyle())

            Text(session.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(session.isRecording ? Color.red.opacity(0.08) : Color(.secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(session.isRecording ? Color.red.opacity(0.22) : .clear, lineWidth: 1)
        }
        .animation(AppAnimation.spring, value: session.isRecording)
    }

    private var liveMetrics: some View {
        HStack(spacing: 12) {
            DriveMetric(title: "Speed", value: "\(Int((session.currentSpeedMetersPerSecond * 2.23694).rounded()))", unit: "mph", symbol: "speedometer")
            DriveMetric(title: "Motion", value: String(format: "%.2f", session.currentHorizontalAccelerationG), unit: "g", symbol: "waveform.path.ecg")
        }
    }

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "What gets measured", subtitle: "A first-pass, on-device drive score — not a safety guarantee.")
            Label("GPS speed changes flag hard braking and rapid acceleration.", systemImage: "location.fill")
            Label("Motion is transformed against gravity and used as corroboration, not as a standalone verdict.", systemImage: "waveform.path.ecg")
            Label("A physical iPhone is required for meaningful sensor data.", systemImage: "iphone")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .premiumCard()
    }

    private var driveHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Past drives", subtitle: "Routes and coaching events stay on this device.")
            ForEach(session.recordedDrives) { drive in
                NavigationLink {
                    DriveDetailView(drive: drive)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "map.fill")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(drive.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline.weight(.semibold))
                            Text("\(String(format: "%.1f", drive.score.distanceMiles)) mi · \(drive.score.events.count) coaching events")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(drive.score.score)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(drive.score.score >= 78 ? .green : .orange)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if drive.id != session.recordedDrives.last?.id { Divider() }
            }
        }
        .premiumCard()
    }

}

private struct DriveDetailView: View {
    let drive: RecordedDrive
    @State private var selectedEvent: DrivingEvent?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drive details").font(AppDesign.Typography.heroTitle)
                    Text(drive.startedAt.formatted(date: .complete, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                }

                if drive.route.count >= 2 {
                    RecordedDriveMapView(route: drive.route, events: drive.score.events) { event in
                        selectedEvent = event
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous))
                } else {
                    ContentUnavailableView("Route unavailable", systemImage: "location.slash", description: Text("This drive did not receive enough accurate GPS fixes to draw a route."))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                        .premiumCard()
                }

                DriveScoreCard(score: drive.score)
                incidentSection
            }
            .padding(.horizontal, AppDesign.contentPadding)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Past drive")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedEvent) { event in
            DriveEventDetail(event: event)
                .presentationDetents([.height(250)])
                .presentationDragIndicator(.visible)
        }
    }

    private var incidentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Coaching events", subtitle: "Tap a map icon or event for details.")
            if drive.score.events.isEmpty {
                Label("No abrupt maneuvers were detected.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(drive.score.events) { event in
                    Button { selectedEvent = event } label: {
                        HStack(spacing: 12) {
                            Image(systemName: event.kind.symbol).foregroundStyle(.orange).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.kind.title).font(.subheadline.weight(.semibold))
                                Text(event.timestamp.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .premiumCard()
    }
}

private struct DriveEventDetail: View {
    let event: DrivingEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: event.kind.symbol).font(.title).foregroundStyle(.orange)
            Text(event.kind.title).font(.title2.weight(.bold))
            Text(event.timestamp.formatted(date: .abbreviated, time: .standard)).foregroundStyle(.secondary)
            Text("Detected from \(event.source.rawValue). This is a coaching signal, not a determination of unsafe driving.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DriveMetric: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            IconTile(symbol: symbol)
            Text(value).font(.title2.monospacedDigit().weight(.semibold))
            Text("\(title) · \(unit)").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard()
    }
}

private struct DriveScoreCard: View {
    let score: DrivingScore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last drive").font(.headline)
                    Text(score.grade).font(.footnote.weight(.semibold)).foregroundStyle(score.dataQuality.confidence == .low ? .orange : (score.score >= 78 ? .green : .orange))
                }
                Spacer()
                Text("\(score.score)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text("/100").font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Text("\(String(format: "%.1f", score.distanceMiles)) mi")
                Spacer()
                Text(score.formattedDuration)
                Spacer()
                Text("Top \(score.topSpeedMPH) mph")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)

            if !score.events.isEmpty {
                Divider()
                ForEach(DrivingEventKind.allCases.filter { score.count(for: $0) > 0 }) { event in
                    HStack {
                        Image(systemName: event.symbol).frame(width: 22).foregroundStyle(.orange)
                        Text(event.title)
                        Text(eventSource(for: event))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("\(score.count(for: event))").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }

            Text(score.summary).font(.footnote).foregroundStyle(.secondary)
            Label(score.dataQuality.summary, systemImage: "checkmark.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .premiumCard()
    }

    private func eventSource(for kind: DrivingEventKind) -> String {
        // Counts are grouped by event kind; source provenance is surfaced in the
        // score summary rather than pretending every occurrence had one source.
        kind == .phoneMovement ? "motion" : "GPS / motion"
    }
}

private struct FlipClock: View {
    let elapsed: TimeInterval
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var digits: [String] {
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return Array(String(format: "%02d%02d", minutes, seconds)).map(String.init)
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(digits.enumerated()), id: \.offset) { index, digit in
                if index == 2 {
                    Text(":")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 1)
                }
                FlipClockDigit(digit: digit, animate: isActive && !reduceMotion)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drive time \(Int(elapsed) / 60) minutes, \(Int(elapsed) % 60) seconds")
    }
}

private struct FlipClockDigit: View {
    let digit: String
    let animate: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black)
            Text(digit)
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.92))
                .contentTransition(.numericText())
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)
        }
        .frame(width: 56, height: 76)
        .animation(animate ? .spring(response: 0.28, dampingFraction: 0.82) : nil, value: digit)
    }
}

private struct DriveHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "lifepreserver.fill")
                .font(.system(size: 30))
                .foregroundStyle(.red)
            Text("Get help safely").font(.title2.weight(.bold))
            Text("If you feel unsafe, pull over in a safe place before using your phone. Swerve cannot contact emergency services or monitor a crash.")
                .foregroundStyle(.secondary)
            Button("Call emergency services") {
                if let number = URL(string: "tel://911") { openURL(number) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    DriveView()
        .environmentObject(DriveSessionManager())
}
