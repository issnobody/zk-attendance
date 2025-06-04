//
//  SignupView.swift
//  DataLogger
//
//  Created by Ayush Sharma on 5/5/25.
//


import SwiftUI

struct SignupView: View {
    @EnvironmentObject var session: SessionStore
    @State private var username = ""
    @State private var password = ""
    @State private var confirm  = ""
    @State private var showingAlert = false

    var body: some View {
        VStack(spacing:20) {
            Text("Sign Up").font(.largeTitle)
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
            SecureField("Confirm", text: $confirm)
                .textFieldStyle(.roundedBorder)

            Button("Create Account") {
                guard password == confirm, !username.isEmpty else {
                    session.errorMessage = "Passwords must match"
                    showingAlert = true
                    return
                }
                session.signup(username: username, password: password) { ok in
                    if ok {
                        // on success, pop back to login
                        showingAlert = true
                        session.errorMessage = "Signup successful—please log in"
                    } else {
                        showingAlert = true
                    }
                }
            }
            .disabled(username.isEmpty || password.isEmpty)
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("Signup"),
                      message: Text(session.errorMessage ?? ""),
                      dismissButton: .default(Text("OK")))
            }
        }
        .padding()
    }
}
