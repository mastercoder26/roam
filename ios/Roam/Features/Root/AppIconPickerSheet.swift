import SwiftUI
import UIKit

struct AppIconPickerSheet: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject var iconManager: AppIconManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.space12) {
                    Text("Pick the icon shown on your Home Screen.")
                        .font(.footnote)
                        .foregroundStyle(AppDesign.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !iconManager.supportsAlternateIcons {
                        Label("This device can't switch app icons.", systemImage: "exclamationmark.circle")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppDesign.safety)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppDesign.safety.opacity(0.12), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
                    } else if let error = iconManager.lastError {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppDesign.danger)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppDesign.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
                    }

                    VStack(spacing: 0) {
                        ForEach(AppIconID.allCases) { iconID in
                            iconRow(iconID)
                            if iconID != AppIconID.allCases.last {
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
            .navigationTitle("App icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func iconRow(_ iconID: AppIconID) -> some View {
        let isSelected = iconManager.currentID == iconID
        let canSelect = iconManager.supportsAlternateIcons

        return Button {
            guard canSelect else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            iconManager.select(iconID)
        } label: {
            AppSelectionRow(title: iconID.title, detail: iconID.subtitle, isSelected: isSelected) {
                iconThumbnail(iconID)
            }
                .opacity(canSelect || isSelected ? 1 : 0.55)
        }
        .buttonStyle(PressableScaleStyle())
        .disabled(!canSelect)
        .accessibilityLabel(iconID.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(canSelect ? iconID.subtitle : "Unavailable on this device")
    }

    private func iconThumbnail(_ iconID: AppIconID) -> some View {
        Image(iconID.previewAssetName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.cornerRadiusTiny, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.cornerRadiusTiny, style: .continuous)
                    .stroke(AppDesign.cardStrokeStrong, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    AppIconPickerSheet(iconManager: AppIconManager.shared)
}
