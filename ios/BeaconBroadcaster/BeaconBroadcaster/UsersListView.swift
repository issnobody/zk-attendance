// UsersListView.swift

import SwiftUI

/// Simple model of an “admin user”
///—must match  `/users` JSON

private struct AdminError: Identifiable {
    let id = UUID()
    let msg: String
}

struct UsersListView: View {
    @EnvironmentObject var session: AdminSessionStore

    @State private var users: [AdminUser] = []
    @State private var isLoading = false
    @State private var alert: AdminError?

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if users.isEmpty {
                    Text("No users found")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(users) { user in
                        NavigationLink(destination: UserHistoryView(user: user)) {
                            Text(user.username)
                        }
                    }
                }
            }
            .navigationTitle("All Users")
            .toolbar {
                // pull-to-refresh button
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        fetchUsers()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .onAppear(perform: fetchUsers)
            .alert(item: $alert) { err in
                Alert(
                    title: Text("Error"),
                    message: Text(err.msg),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func fetchUsers() {
        guard let token = session.token else {
            alert = AdminError(msg: "Not authenticated")
            return
        }

        isLoading = true
        alert     = nil

        let url = session.baseURL.appendingPathComponent("users")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                isLoading = false

                if let err = err {
                    alert = AdminError(msg: err.localizedDescription)
                    return
                }
                guard let data = data else {
                    alert = AdminError(msg: "No data received")
                    return
                }
                do {
                    users = try JSONDecoder().decode([AdminUser].self, from: data)
                } catch {
                    alert = AdminError(msg: "Failed to decode users: \(error)")
                }
            }
        }
        .resume()
    }
}
