import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: SessionStore
    @State private var username = ""
    @State private var password = ""
    @State private var showSignup = false

    var body: some View {
        VStack(spacing:20) {
            Text("ZK Attendance").font(.largeTitle)
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            Button("Log In") {
                session.login(username: username, password: password) { ok in
                    if !ok {
                        // show error alert
                        showSignup = false
                    }
                }
            }
            .disabled(username.isEmpty || password.isEmpty)
            .alert(item: Binding(
              get: { session.errorMessage.map { ErrorWrapper($0) } },
              set: { _ in session.errorMessage = nil }
            )) { err in
                Alert(title: Text("Login Error"), message: Text(err.msg), dismissButton: .default(Text("OK")))
            }

            Button("Sign Up") {
                showSignup = true
            }
            .sheet(isPresented: $showSignup) {
                SignupView().environmentObject(session)
            }
        }
        .padding()
    }
}

// helper to use String in alert(item:)
struct ErrorWrapper: Identifiable {
    let id = UUID()
    let msg: String
    init(_ m:String){msg=m}
}
