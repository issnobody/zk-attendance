import SwiftUI

@main
struct ProverApp: App {
  @StateObject var session = SessionStore()

  var body: some Scene {
    WindowGroup {
      if session.isLoggedIn {
        HomeView()
          .environmentObject(session)
      } else {
        LoginView()
          .environmentObject(session)
      }
    }
  }
}


