import Foundation
import SwiftUI

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?

    private let auth: AuthManager
    private let onSuccess: @MainActor () -> Void

    init(auth: AuthManager, onSuccess: @escaping @MainActor () -> Void = {}) {
        self.auth = auth
        self.onSuccess = onSuccess
    }

    func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        guard Self.isValidEmail(email) else {
            errorMessage = "Enter a valid email address."
            return
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }

        isSubmitting = true
        var passwordCopy = password
        defer {
            passwordCopy.removeAll(keepingCapacity: false)
            password = ""
            isSubmitting = false
        }

        do {
            try await auth.login(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: passwordCopy)
            onSuccess()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private static func isValidEmail(_ value: String) -> Bool {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = email.firstIndex(of: "@"), at > email.startIndex else { return false }
        let domain = email[email.index(after: at)...]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    private static func message(for error: Error) -> String {
        guard let appError = error as? AppError else {
            return "Unable to sign in."
        }
        return switch appError {
        case .loginRequired:
            "Sign-in is required."
        case .unauthorized:
            "Email or password is incorrect."
        default:
            "Unable to sign in."
        }
    }
}
