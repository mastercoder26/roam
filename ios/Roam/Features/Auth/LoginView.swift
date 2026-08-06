import SwiftUI

/// A visual account entry point for the prototype. The controls intentionally
/// stop at presentation for now; wiring authentication can happen without
/// changing the screen's hierarchy or copy.
struct LoginView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var email = ""
    @State private var password = ""
    @State private var showingComingSoon = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email
        case password
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                credentialsCard
                providerDivider
                providerButtons
                footer
            }
            .padding(.horizontal, AppDesign.contentPadding)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(loginBackground)
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .tint(AppDesign.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrandWordmark()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome back")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .tracking(-0.7)
                    .foregroundStyle(AppDesign.Ink.primary)
                    .accessibilityAddTraits(.isHeader)

                Text("Sign in to keep your driving history and progress together.")
                    .font(.body)
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your account")
                .font(.headline)
                .foregroundStyle(AppDesign.Ink.primary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppDesign.Ink.secondary)

                HStack(spacing: 10) {
                    Image(systemName: "envelope")
                        .foregroundStyle(AppDesign.Ink.tertiary)
                        .frame(width: 20)

                    TextField("you@example.com", text: $email)
                        .font(AppDesign.Typography.body)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .accessibilityLabel("Email address")
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(AppDesign.cardSurfaceElevated, in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous)
                        .stroke(focusedField == .email ? AppDesign.accent : AppDesign.cardStroke, lineWidth: focusedField == .email ? 1.5 : 1)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Password")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppDesign.Ink.secondary)
                    Spacer()
                    Button("Forgot password?") { placeholderAction() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppDesign.accent)
                        .frame(minHeight: 44, alignment: .trailing)
                        .buttonStyle(PressableScaleStyle())
                        .accessibilityHint("Password recovery will be available soon")
                }

                HStack(spacing: 10) {
                    Image(systemName: "lock")
                        .foregroundStyle(AppDesign.Ink.tertiary)
                        .frame(width: 20)

                    SecureField("Enter your password", text: $password)
                        .font(AppDesign.Typography.body)
                        .textContentType(.password)
                        .accessibilityLabel("Password")
                        .focused($focusedField, equals: .password)
                        .submitLabel(.done)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(AppDesign.cardSurfaceElevated, in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous)
                        .stroke(focusedField == .password ? AppDesign.accent : AppDesign.cardStroke, lineWidth: focusedField == .password ? 1.5 : 1)
                }
            }

            Button { placeholderAction() }
            label: {
                Text("Sign in")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .foregroundStyle(AppDesign.accentForeground)
                    .background(AppDesign.accent, in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
            }
            .buttonStyle(PressableScaleStyle())
            .accessibilityHint("Sign-in is not connected in this prototype")
        }
        .premiumCard()
    }

    private var providerDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(AppDesign.cardStroke)
                .frame(height: 1)
            Text("or continue with")
                .font(.caption)
                .foregroundStyle(AppDesign.Ink.tertiary)
                .fixedSize()
            Rectangle()
                .fill(AppDesign.cardStroke)
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    private var providerButtons: some View {
        VStack(spacing: 10) {
            AuthProviderButton(title: "Continue with Apple", symbol: "apple.logo", action: placeholderAction)
            AuthProviderButton(title: "Continue with Google", symbol: "globe", action: placeholderAction)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if showingComingSoon {
                Label("Authentication is being prepared for this prototype.", systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }

            Button { placeholderAction() }
            label: {
                Text("New to Roam? Create an account")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppDesign.accent)
                    .frame(minHeight: 44)
            }
            .buttonStyle(PressableScaleStyle())
            .accessibilityHint("Account creation will be available soon")
        }
        .animation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.quick, value: showingComingSoon)
    }

    private func placeholderAction() {
        showingComingSoon = true
    }

    private var loginBackground: some View {
        ZStack {
            AppDesign.canvas

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppDesign.accent.opacity(0.16), AppDesign.accent.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 220
                    )
                )
                .frame(width: 440, height: 440)
                .offset(x: 150, y: -300)
                .blur(radius: 12)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }
}

private struct AuthProviderButton: View {
    @ObservedObject private var theme = ThemeManager.shared
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .frame(width: 20)

                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 0)
            }
            .foregroundStyle(AppDesign.Ink.primary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(AppDesign.cardSurface, in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous)
                    .stroke(AppDesign.cardStroke, lineWidth: 1)
            }
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityHint("This sign-in option is not connected in the prototype")
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
    .environmentObject(DriveSessionManager.shared)
}
