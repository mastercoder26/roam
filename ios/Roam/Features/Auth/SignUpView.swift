import SwiftUI
import UIKit

struct SignUpView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var authSession: AuthSessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var displayName = ""
    @State private var emailError: String?
    @State private var passwordError: String?
    @State private var confirmationError: String?
    @State private var formError: AuthError?
    @State private var isSubmitting = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email
        case password
        case confirmation
        case displayName
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                formCard
                footer
            }
            .padding(.horizontal, AppDesign.contentPadding)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppDesign.canvas.ignoresSafeArea())
        .navigationTitle("Create an account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .tint(AppDesign.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrandWordmark().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Make Roam yours")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .tracking(-0.7)
                    .foregroundStyle(AppDesign.Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Text("Create an account to sync your progress. Your drives still work fully on this device if you stay signed out.")
                    .font(.body)
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let formError {
                AuthFormErrorBanner(error: formError, onRetry: formError.isTransient ? submit : nil) {
                    self.formError = nil
                }
            }

            authField(title: "Email", error: emailError) {
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

            authField(title: "Password", error: passwordError) {
                SecureField("At least 8 characters", text: $password)
                    .font(AppDesign.Typography.body)
                    .textContentType(.newPassword)
                    .accessibilityLabel("Password")
                    .focused($focusedField, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .confirmation }
                    .fieldContainer(isFocused: focusedField == .password)
            }

            authField(title: "Confirm password", error: confirmationError) {
                SecureField("Enter your password again", text: $confirmation)
                    .font(AppDesign.Typography.body)
                    .textContentType(.newPassword)
                    .accessibilityLabel("Confirm password")
                    .focused($focusedField, equals: .confirmation)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .displayName }
                    .fieldContainer(isFocused: focusedField == .confirmation)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Display name (optional)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppDesign.Ink.secondary)
                TextField("What should we call you?", text: $displayName)
                    .font(AppDesign.Typography.body)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .textContentType(.name)
                    .accessibilityLabel("Display name, optional")
                    .focused($focusedField, equals: .displayName)
                    .submitLabel(.done)
                    .onSubmit { submit() }
                    .fieldContainer(isFocused: focusedField == .displayName)
            }

            Button(action: submit) {
                Group {
                    if isSubmitting {
                        ProgressView().tint(AppDesign.accentForeground)
                    } else {
                        Text("Create account")
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
            .accessibilityHint("Creates your Roam account and syncs your local profile")
        }
        .premiumCard()
        .animation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.quick, value: formError != nil)
    }

    private func authField<Content: View>(title: String, error: String?, @ViewBuilder content: () -> Content) -> some View {
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

    private var footer: some View {
        NavigationLink(destination: LoginView()) {
            Text("Already have an account? Sign in")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppDesign.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityHint("Returns to the sign-in form")
    }

    private func submit() {
        guard !isSubmitting else { return }
        emailError = nil
        passwordError = nil
        confirmationError = nil
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
        guard password == confirmation else {
            confirmationError = "Passwords do not match."
            focusedField = .confirmation
            return
        }

        isSubmitting = true
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            defer { isSubmitting = false }
            do {
                try await authSession.signUp(email: normalizedEmail, password: password, displayName: name.isEmpty ? nil : name)
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
}

#Preview {
    NavigationStack { SignUpView() }
        .environmentObject(AuthSessionStore.shared)
}
