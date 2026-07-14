import SwiftUI

struct DriveView: View {
    @StateObject private var session = DriveSessionManager()
    @State private var showingHelp = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                    header
                    recordingCard
                    liveMetrics

                    if let score = session.lastScore, !session.isRecording {
                        DriveScoreCard(score: score)
                    } else {
                        howItWorksCard
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

    private var recordingCard: some View {
        VStack(spacing: 18) {
            HStack {
                Label(session.isRecording ? "DRIVE IN PROGRESS" : "MANUAL DRIVE", systemImage: session.isRecording ? "record.circle.fill" : "steeringwheel")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(session.isRecording ? .red : .secondary)
                Spacer()
                Text(timeString(session.elapsed))
                    .font(.title3.monospacedDigit().weight(.semibold))
            }

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
            DriveMetric(title: "Motion", value: "\(session.motionSamples)", unit: "samples", symbol: "waveform.path.ecg")
        }
    }

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "What gets measured", subtitle: "A first-pass, on-device drive score — not a safety guarantee.")
            Label("GPS speed changes flag hard braking and rapid acceleration.", systemImage: "location.fill")
            Label("Phone motion highlights abrupt movement without assuming the phone is mounted perfectly.", systemImage: "waveform.path.ecg")
            Label("A physical iPhone is required for meaningful sensor data.", systemImage: "iphone")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .premiumCard()
    }

    private func timeString(_ time: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(time) / 60, Int(time) % 60)
    }
}

private struct DriveMetric: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Color.accentColor)
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
                    Text(score.grade).font(.footnote.weight(.semibold)).foregroundStyle(score.score >= 78 ? .green : .orange)
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
                        Spacer()
                        Text("\(score.count(for: event))").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }

            Text(score.summary).font(.footnote).foregroundStyle(.secondary)
        }
        .premiumCard()
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
}
