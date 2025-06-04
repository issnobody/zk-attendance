import SwiftUI

///  existing single‐view broadcaster UI
struct BroadcastView: View {
  @EnvironmentObject var broadcaster: BeaconBroadcaster

  var body: some View {
    Text("🔊 Beacon Broadcaster Running…")
      .multilineTextAlignment(.center)
      .padding()
      .onAppear { /* nothing to do here—the manager lives in App */ }
  }
}
