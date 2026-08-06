import SwiftUI

struct LoginView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var authSession: AuthSessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var email = ""
    @State private var password = ""
    @State private var emailError: String?
    @State private var passwordError: String?
    @State private var formError: AuthError?
    @State private var isSubmitting = false
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

            if formError != nil {
                loginBanner
                    .transition(.opacity)
            }

            labeledField(title: "Email", error: emailError) {
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
                .fieldContainer(isFocused: focusedField == .email)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Password")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppDesign.Ink.secondary)
                    Spacer()
                    NavigationLink("Forgot password?", destination: ForgotPasswordView())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppDesign.accent)
                        .frame(minHeight: 44, alignment: .trailing)
                        .buttonStyle(PressableScaleStyle())
                        .accessibilityHint("Opens honest recovery options and support contact details")
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
                        .onSubmit { submit() }
                }
                .fieldContainer(isFocused: focusedField == .password)

                if let passwordError {
                    AuthFieldError(text: passwordError)
                }
            }

            Button(action: submit) {
                Group {
                    if isSubmitting {
                        ProgressView()
                            .tint(AppDesign.accentForeground)
                    } else {
                        Text("Sign in")
                    }
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .foregroundStyle(AppDesign.accentForeground)
                .background(AppDesign.accent, in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
            }
            .buttonStyle(PressableScaleStyle())
            .disabled(isSubmitting)
            .accessibilityHint("Signs in and syncs your local profile when the server is available")
        }
        .premiumCard()
    }

    private func labeledField<Content: View>(title: String, error: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppDesign.Ink.secondary)
            content()
            if let error {
                AuthFieldError(text: error)
            }
        }
    }

    private var providerDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(AppDesign.cardStroke).frame(height: 1)
            Text("or continue with")
                .font(.caption)
                .foregroundStyle(AppDesign.Ink.tertiary)
                .fixedSize()
            Rectangle().fill(AppDesign.cardStroke).frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    private var providerButtons: some View {
        VStack(spacing: 10) {
            // The backend would need POST /api/auth/apple to exchange an Apple identity token.
            AuthProviderButton(title: "Continue with Apple", symbol: "apple.logo")
            // The backend would need POST /api/auth/google to exchange a Google identity token.
            AuthProviderButton(title: "Continue with Google", symbol: "globe")
        }
    }

    private var footer: some View {
        NavigationLink(destination: SignUpView()) {
            Text("New to Roam? Create an account")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppDesign.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityHint("Opens the account creation form")
        .animation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.quick, value: formError != nil)
    }

    @ViewBuilder
    private var loginBanner: some View {
        if let formError {
            AuthFormErrorBanner(error: formError, onRetry: formError.isTransient ? submit : nil) {
                self.formError = nil
            }
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        emailError = nil
        passwordError = nil
        formError = nil

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(normalizedEmail) else {
            emailError = "Enter a valid email address."
            focusedField = .email
            return
        }
        guard password.count >= 8 else {
            passwordError = "Use at least 8 characters."
            focusedField = .password
            return
        }

        isSubmitting = true
        Task { @MainActor in
            defer { isSubmitting = false }
            do {
                try await authSession.signIn(email: normalizedEmail, password: password)
                dismiss()
            } catch let error as AuthError {
                if error.code == .emailTaken {
                    emailError = error.localizedDescription
                } else {
                    formError = error
                }
            } catch {
                formError = .serverUnavailable
            }
        }
    }

    private static func isValidEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        return parts[1].contains(".") && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".")
    }

    private var loginBackground: some View {
        ZStack {
            AppDesign.canvas
            Circle()
                .fill(RadialGradient(colors: [AppDesign.accent.opacity(0.16), AppDesign.accent.opacity(0)], center: .center, startRadius: 0, endRadius: 220))
                .frame(width: 440, height: 440)
                .offset(x: 150, y: -300)
                .blur(radius: 12)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }
}

extension View {
    func fieldContainer(isFocused: Bool) -> some View {
        padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(AppDesign.cardSurfaceElevated, in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous)
                    .stroke(isFocused ? AppDesign.accent : AppDesign.cardStroke, lineWidth: isFocused ? 1.5 : 1)
            }
    }
}

struct AuthFieldError: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(AppDesign.danger)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(text)
    }
}

struct AuthFormErrorBanner: View {
    let error: AuthError
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(AppDesign.Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let onRetry {
                Button("Retry", action: onRetry)
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 44)
                    .buttonStyle(PressableScaleStyle())
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Dismiss message")
        }
        .padding(12)
        .background(AppDesign.cardSurface, in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous)
                .stroke(AppDesign.cardStroke, lineWidth: 1)
        }
    }
}

struct AuthProviderButton: View {
    let title: String
    let symbol: String

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .frame(width: 20)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Text("Not available yet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppDesign.Ink.tertiary)
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
        .disabled(true)
        .accessibilityHint("This provider option is not available yet")
    }
}

#Preview {
    NavigationStack { LoginView() }
        .environmentObject(DriveSessionManager.shared)
        .environmentObject(AuthSessionStore.shared)
}
