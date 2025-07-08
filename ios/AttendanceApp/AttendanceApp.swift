import SwiftUI
import CoreLocation

@main
struct AttendanceApp: App {
    @StateObject private var rootSession = RootSession()
    @StateObject private var broadcaster = BeaconBroadcaster()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            switch rootSession.role {
            case .student:
                HomeView()
                    .environmentObject(rootSession.student)
            case .admin:
                MainTabView()
                    .environmentObject(rootSession.admin)
                    .environmentObject(broadcaster)
            case .none:
                AppLoginView()
                    .environmentObject(rootSession)
            }
        }
    }
}

// copied from BeaconBroadcasterApp so location permissions work
class AppDelegate: NSObject, UIApplicationDelegate, CLLocationManagerDelegate {
    private let locMgr = CLLocationManager()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        locMgr.delegate = self
        locMgr.requestWhenInUseAuthorization()
        return true
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }
}
