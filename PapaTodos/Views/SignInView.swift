import SwiftUI

struct SignInView: View {
    let reason: AppSession.SignedOutReason?

    @Environment(AppSession.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
            } header: {
                Text("Sign in to Papa Tools")
            } footer: {
                if let message = bannerMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("signin.message")
                }
            }

            Section {
                Button(action: submit) {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign In")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!canSubmit)
                .accessibilityIdentifier("signin.submit")
            }
        }
    }

    private var bannerMessage: String? {
        errorMessage ?? (reason == .sessionExpired ? DataServiceError.sessionExpired.errorDescription : nil)
    }

    private var canSubmit: Bool {
        !isSubmitting && !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await session.signIn(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            } catch {
                errorMessage = (error as? DataServiceError)?.errorDescription
                    ?? DataServiceError.server.errorDescription
            }
            isSubmitting = false
        }
    }
}
