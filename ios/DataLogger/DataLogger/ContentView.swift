import SwiftUI
import CoreMotion

struct ContentView: View {
    @State private var label = "WITH"
    @State private var rows: [String] = []
    private let motion = CMMotionManager()

    var body: some View {
        VStack(spacing: 24) {
            Picker("Label", selection: $label) {
                Text("WITH").tag("WITH")
                Text("LEFT").tag("LEFT")
            }
            .pickerStyle(SegmentedPickerStyle())
            
            Button("Start Logging") {
                start()
            }
            .padding(.horizontal)
            
            Button("Stop & Export") {
                export()
            }
            .padding(.horizontal)
        }
        .padding()
        .onAppear {
            print("🛠️ ContentView appeared")
        }
    }

    private func start() {
        print("🔴 start() called, isDeviceMotionAvailable = \(motion.isDeviceMotionAvailable)")
        rows.removeAll()

        guard motion.isDeviceMotionAvailable else {
            print("⚠️ DeviceMotion not available on this device")
            return
        }

        motion.deviceMotionUpdateInterval = 0.02  // 50 Hz
        motion.startDeviceMotionUpdates(to: .main) { data, error in
            if let err = error {
                print("❌ Motion update error:", err.localizedDescription)
                return
            }
            guard let d = data else { return }
            let ts = Date().timeIntervalSince1970
            let row = [
                String(ts),
                String(d.userAcceleration.x),
                String(d.userAcceleration.y),
                String(d.userAcceleration.z),
                String(d.rotationRate.x),
                String(d.rotationRate.y),
                String(d.rotationRate.z),
                label
            ].joined(separator: ",")
            rows.append(row)
        }
    }

    private func export() {
        print("🟢 export() called, row count = \(rows.count)")
        motion.stopDeviceMotionUpdates()
        let csv = rows.joined(separator: "\n")
        let filename = "log_\(label).csv"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            print("CSV saved ➜ \(url.path) (\(rows.count) rows)")
        } catch {
            print("❌ Failed to save CSV:", error.localizedDescription)
        }
    }
}
