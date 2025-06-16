import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var session: SessionStore

    // 1️⃣ Add a DateFormatter that prints both date & time
    static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateStyle  = .medium    // e.g. “May  6, 2025”
        f.timeStyle  = .short     // e.g. “3:18 PM”
        return f
    }()

    var body: some View {
        NavigationView {
            List(session.history) { rec in
                HStack {
                    Text(rec.date, formatter: Self.dateTimeFormatter)
                    Spacer()
                    Text(rec.status)
                        .foregroundColor(
                            rec.status.hasPrefix("✅")
                              ? .green
                              : .red
                        )
                }
            }
            .refreshable { session.fetchHistory() }
            .onAppear { session.fetchHistory() }
            .navigationTitle("Attendance History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Logout") {
                        session.logout()
                    }
                }
            }
        }
    }
}
