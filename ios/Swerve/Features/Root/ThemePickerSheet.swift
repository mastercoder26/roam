import SwiftUI
import UIKit

struct ThemePickerSheet: View {
    @ObservedObject var themeManager: ThemeManager
    @EnvironmentObject private var driveSession: DriveSessionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canChangeTheme: Bool {
        !driveSession.isRecording
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Color schemes")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppDesign.Ink.primary)
                    Text("Tap Swerve anytime to change the look. Your choice stays on this device.")
                        .font(.footnote)
                        .foregroundStyle(AppDesign.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !canChangeTheme {
                        Label("Finish your drive before switching themes.", systemImage: "steeringwheel")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppDesign.safety)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppDesign.safety.opacity(0.12), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
                    }

                    ForEach(ThemeID.allCases) { themeID in
                        themeRow(themeID)
                    }
                }
                .padding(20)
            }
            .background(AppDesign.canvas.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .environmentObject(driveSession)
    }

    private func themeRow(_ themeID: ThemeID) -> some View {
        let palette = ThemeCatalog.palette(for: themeID)
        let isSelected = themeManager.currentID == themeID

        return Button {
            guard canChangeTheme else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : AppAnimation.content) {
                themeManager.select(themeID)
            }
        } label: {
            HStack(spacing: 14) {
                themeSwatch(palette)

                VStack(alignment: .leading, spacing: 3) {
                    Text(themeID.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppDesign.Ink.primary)
                    Text(themeID.subtitle)
                        .font(.caption)
                        .foregroundStyle(AppDesign.Ink.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppDesign.accent : AppDesign.Ink.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
                    .fill(AppDesign.cardSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
                    .stroke(
                        isSelected ? AppDesign.accent.opacity(0.45) : AppDesign.cardStroke,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .opacity(canChangeTheme || isSelected ? 1 : 0.55)
        }
        .buttonStyle(PressableScaleStyle())
        .disabled(!canChangeTheme)
        .accessibilityLabel(themeID.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(canChangeTheme ? themeID.subtitle : "Unavailable while a drive is in progress")
    }

    private func themeSwatch(_ palette: ThemePalette) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.canvas.color)
            Circle()
                .fill(palette.accent.color)
                .frame(width: 18, height: 18)
                .offset(x: 8, y: 6)
            Circle()
                .fill(palette.cardSurface.color)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(palette.cardStroke.color, lineWidth: 1))
                .offset(x: -7, y: -5)
        }
        .frame(width: 44, height: 44)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.cardStrokeStrong.color, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ThemePickerSheet(themeManager: ThemeManager.shared)
        .environmentObject(DriveSessionManager())
}
