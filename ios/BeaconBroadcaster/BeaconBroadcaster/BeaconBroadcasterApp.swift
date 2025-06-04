// BeaconBroadcasterApp.swift

import SwiftUI
import CoreLocation

@main
struct BeaconBroadcasterApp: App {
    // Wire up  AppDelegate so CoreLocation permissions work
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    //  admin login/session store
    @StateObject var adminSession = AdminSessionStore()

    // Keep  beacon‐advertiser alive and inject if needed
    @StateObject var broadcaster = BeaconBroadcaster()

    var body: some Scene {
        WindowGroup {
            if adminSession.isLoggedIn {
                // Logged in → show your main tab UI
                MainTabView()
                  .environmentObject(adminSession)
                  .environmentObject(broadcaster)
            } else {
                // Not logged in → show admin login
                AdminLoginView()
                  .environmentObject(adminSession)
                  // no need to inject broadcaster here unless you use it
            }
        }
    }
}


class AppDelegate: NSObject, UIApplicationDelegate, CLLocationManagerDelegate {
    private let locMgr = CLLocationManager()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        locMgr.delegate = self
        locMgr.requestWhenInUseAuthorization()  // first ask When-In-Use
        return true
    }

    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        if status == .authorizedWhenInUse {
            // once granted When-In-Use, ask for Always
            manager.requestAlwaysAuthorization()
        }
    }
}
