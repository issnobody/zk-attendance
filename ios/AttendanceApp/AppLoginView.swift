import SwiftUI

private struct ErrorWrapper: Identifiable {
    let id = UUID()
    let msg: String
}

struct AppLoginView: View {
    @EnvironmentObject var session: RootSession
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            Text("ZK Attendance")
                .font(.largeTitle.bold())
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            Button(action: {
                session.login(username: username, password: password)
            }) {
                Text("Log In")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(username.isEmpty || password.isEmpty)
        }
        .padding()
        .alert(item: Binding<ErrorWrapper?>(
            get: { session.errorMessage.map { ErrorWrapper(msg: $0) } },
            set: { _ in session.errorMessage = nil }
        )) { err in
            Alert(title: Text("Login Error"), message: Text(err.msg), dismissButton: .default(Text("OK")))
        }
    }
}
