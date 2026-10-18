import SwiftUI
import UIKit

struct ThemePickerSheet: View {
    @ObservedObject private var theme = ThemeManager.shared
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
                VStack(alignment: .leading, spacing: AppDesign.space12) {
                    Text("Choose the colors that feel right for you.")
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

                    VStack(spacing: 0) {
                        ForEach(ThemeID.allCases) { themeID in
                            themeRow(themeID)
                            if themeID != ThemeID.allCases.last {
                                Divider()
                                    .padding(.leading, 80)
                            }
                        }
                    }
                    .menuSurface()
                }
                .padding(.horizontal, AppDesign.contentPadding)
                .padding(.top, AppDesign.space16)
                .padding(.bottom, AppDesign.space24)
                .frame(maxWidth: AppDesign.maximumContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(AppDesign.canvas.ignoresSafeArea())
            .navigationTitle("Color scheme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(themeManager.preferredColorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(themeManager.preferredColorScheme)
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
            AppSelectionRow(title: themeID.title, detail: themeID.subtitle, isSelected: isSelected) {
                themeSwatch(palette)
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
            RoundedRectangle(cornerRadius: AppDesign.cornerRadiusTiny, style: .continuous)
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
            RoundedRectangle(cornerRadius: AppDesign.cornerRadiusTiny, style: .continuous)
                .stroke(palette.cardStrokeStrong.color, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ThemePickerSheet(themeManager: ThemeManager.shared)
        .environmentObject(DriveSessionManager())
}
