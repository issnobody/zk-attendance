// HomeView.swift

import SwiftUI

struct HomeView: View {
  var body: some View {
    TabView {
      AttendanceView()
        .tabItem { Label("Attendance", systemImage: "person.fill.checkmark") }
      HistoryView()
        .tabItem { Label("History",    systemImage: "clock.fill") }
    }
  }
}
