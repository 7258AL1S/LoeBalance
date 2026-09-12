import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: LoginViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LoeBalance")
                .font(.title2.weight(.semibold))

            TextField("Email", text: $viewModel.email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
                .disabled(viewModel.isSubmitting)

            SecureField("Password", text: $viewModel.password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .disabled(viewModel.isSubmitting)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Spacer()
                if viewModel.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Sign In") {
                    Task { await viewModel.submit() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isSubmitting)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}
