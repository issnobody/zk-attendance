// MainTabView.swift

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var adminSession: AdminSessionStore
    @EnvironmentObject var broadcaster: BeaconBroadcaster

    var body: some View {
        TabView {
            // Broadcast screen
            BroadcastView()
                .tabItem {
                    Label("Broadcast", systemImage: "antenna.radiowaves.left.and.right")
                }

            // Admin / Users list screen
            UsersListView()
                .tabItem {
                    Label("Users", systemImage: "person.3.fill")
                }
        }
        .tint(.blue)
    }
}
