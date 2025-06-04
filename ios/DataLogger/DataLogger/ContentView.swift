import SwiftUI
import CoreMotion

enum LogLabel: String, CaseIterable, Identifiable {
    case DESK, HANDSTILL, HANDMOVE, POCKET
    var id: String { rawValue }
}

struct ContentView: View {
    @State private var label: LogLabel = .DESK
    @State private var rows: [String] = []
    private let motion = CMMotionManager()

    var body: some View {
        VStack(spacing: 24) {
            Picker("Label", selection: $label) {
                ForEach(LogLabel.allCases) { lbl in
                    Text(lbl.rawValue).tag(lbl)
                }
            }
            .pickerStyle(.segmented)

            Button("Start Logging") { start() }
            Button("Stop & Export") { export() }
        }
        .padding()
        .onAppear { print("Logger ready for \(label.rawValue) data") }
    }

    private func start() {
        print("🔴 start() \(label.rawValue)")
        rows.removeAll()
        motion.deviceMotionUpdateInterval = 0.02
        motion.startDeviceMotionUpdates(to: .main) { data, _ in
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
                label.rawValue
            ].joined(separator: ",")
            rows.append(row)
        }
    }

    private func export() {
        print("🟢 export() \(rows.count) rows")
        motion.stopDeviceMotionUpdates()
        let csv = rows.joined(separator: "\n")
        let filename = "log_\(label.rawValue).csv"
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(filename)
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        print("CSV saved ➜ \(url.path)")
    }
}




