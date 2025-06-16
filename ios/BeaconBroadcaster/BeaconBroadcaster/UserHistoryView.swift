// UserHistoryView.swift

import SwiftUI

/// Error wrapper for showing alerts
private struct AdminError: Identifiable {
  let id = UUID()
  let msg: String
}

struct UserHistoryView: View {
  @EnvironmentObject var session: AdminSessionStore
  let user: AdminUser

  static let dateTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()

  var body: some View {
    List {
      if session.selectedHistory.isEmpty {
        Text("Fetching records…")
      }
      ForEach(session.selectedHistory) { rec in
        HStack {
          Text(rec.date, formatter: Self.dateTimeFormatter)
          Spacer()
          Text(rec.status)
            .foregroundColor(rec.status.hasPrefix("✅") ? .green : .red)
        }
      }
    }
    .navigationTitle(user.username)
    .onAppear {
      session.fetchHistory(for: user)
    }
    .alert(item: Binding<AdminError?>(
      get: { session.errorMessage.map { AdminError(msg: $0) } },
      set: { _ in session.errorMessage = nil }
    )) { err in
      Alert(title: Text("Error"), message: Text(err.msg), dismissButton: .default(Text("OK")))
    }
  }
}
