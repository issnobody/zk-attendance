// AdminLoginView.swift

import SwiftUI

// A simple Identifiable wrapper so we can show session.errorMessage in an alert
private struct AdminError: Identifiable {
    let id = UUID()
    let msg: String
}

struct AdminLoginView: View {
    @EnvironmentObject var session: AdminSessionStore
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            Text("Admin Login")
                .font(.largeTitle)
                .bold()

            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            Button(action: {
                // Call the login API; onSuccess session.isLoggedIn → true
                session.login(username: username, password: password) { _ in }
            }) {
                Text("Log In")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(username.isEmpty || password.isEmpty)

            Spacer()
        }
        .padding()
        // Show any error from AdminSessionStore.errorMessage
        .alert(item: Binding<AdminError?>(
            get: {
                session.errorMessage.map { AdminError(msg: $0) }
            },
            set: { _ in
                session.errorMessage = nil
            }
        )) { error in
            Alert(
                title: Text("Login Error"),
                message: Text(error.msg),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
