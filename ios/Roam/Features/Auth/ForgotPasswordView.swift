import SwiftUI

struct ForgotPasswordView: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BrandWordmark()
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Password recovery")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .tracking(-0.7)
                        .foregroundStyle(AppDesign.Ink.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Recovery is not available in Roam yet, so we will not ask you to enter an email into a dead form.")
                        .font(.body)
                        .foregroundStyle(AppDesign.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label("What you can do now", systemImage: "lifepreserver.fill")
                        .font(.headline)
                        .foregroundStyle(AppDesign.Ink.primary)
                    Text("Contact the Roam team through support and include the email you use for Roam. They can help with the next step while password recovery is being built.")
                        .font(.body)
                        .foregroundStyle(AppDesign.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label("Next step: use the Roam support channel you already use and include the email on your account.", systemImage: "envelope")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppDesign.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .premiumCard()
            }
            .padding(.horizontal, AppDesign.contentPadding)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .background(AppDesign.canvas.ignoresSafeArea())
        .navigationTitle("Password recovery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

#Preview {
    NavigationStack { ForgotPasswordView() }
}
