import SwiftUI
import CoreMotion
import CoreML
import Combine
import AnyCodable

struct AttendanceView: View {
    @EnvironmentObject var session: SessionStore

    // ─── Beacon scanning ───
    @StateObject private var scanner = BLEScanner()
    @State private var lastBeaconTime = Date()
    @State private var outOfRange = false

    // ─── Motion + RF presence detection ───
    private let motion = CMMotionManager()
    @State private var buffer: [[Double]] = []
    @State private var sampleCount = 0
    @State private var resultText = "Idle"
    @State private var lastResults: [Bool] = [true, true]
    @State private var instantStates: [Bool] = []        // collect instant states
    private let rfModel: PresenceRF = {
        let cfg = MLModelConfiguration()
        return try! PresenceRF(configuration: cfg)
    }()
    private let windowSize      = 100   // 2s @50Hz
    private let hopSize         = 50    // 1s @50Hz
    private let ratioThreshold  = 5.0

    // ─── Proof state ───
    @State private var lastSentNonce: Data? = nil
    @State private var proofResult = ""

    // ─── 3-minute sampling state ───
    @State private var samples: [Bool] = []
    @State private var finalText = ""
    @State private var samplingTimer: Timer?
    @State private var attendanceTimer: Timer?

    // ─── Timing constants ───
    private let rangeThreshold    : TimeInterval = 35    // seconds until "out of range"
    private let samplingInterval  : TimeInterval = 20    // sample every 20s
    private let attendanceWindow  : TimeInterval = 180   // 3 minutes
    private let firstSampleDelay  : TimeInterval = 5     // wait 5s before 1st sample

    // ─── Timers as publishers ───
    private let rangeTimer = Timer.publish(every: 1, on: .main, in: .common)
                                 .autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            Text("Realtime State")
              .font(.headline)

            Text(resultText)
              .font(.largeTitle)
              .foregroundColor(resultText == "WITH USER" ? .green : .red)

            Text(outOfRange ? "OUT OF RANGE" : "IN RANGE")
              .font(.subheadline)
              .foregroundColor(outOfRange ? .orange : .secondary)

            if !finalText.isEmpty {
                Text(finalText)
                  .font(.title2)
                  .padding(.top)
            }

            Button("Start Capture & Scan") {
                startContinuousCapture()
                lastBeaconTime = Date()
                startSampling()
            }
            .padding(.top)

            Text(proofResult)
              .font(.footnote)
              .foregroundColor(.blue)
              .padding(.top, 8)
        }
        .padding()
        // ─── Range check ───
        .onReceive(rangeTimer) { _ in
            let elapsed = Date().timeIntervalSince(lastBeaconTime)
            outOfRange = (elapsed > rangeThreshold)
        }
        // ─── Beacon nonce handling ───
        .onReceive(scanner.noncePublisher) { nonce in
            lastBeaconTime = Date()
            guard resultText == "WITH USER",
                  nonce != lastSentNonce
            else { return }
            lastSentNonce = nonce

            proofResult = "Generating proof…"
            generateAndSendProof(nonce: nonce)
        }
        .onAppear {
            print("AttendanceView ready")
        }
    }

    // MARK: Motion capture & classification

    func startContinuousCapture() {
        buffer.removeAll()
        sampleCount = 0
        lastResults = [true, true]
        resultText = "Capturing…"
        instantStates.removeAll()

        guard motion.isDeviceMotionAvailable else {
            resultText = "Motion unavailable"
            return
        }
        motion.deviceMotionUpdateInterval = 1.0/50.0
        motion.startDeviceMotionUpdates(to: .main) { data, _ in
            guard let d = data else { return }
            buffer.append([
                d.userAcceleration.x, d.userAcceleration.y, d.userAcceleration.z,
                d.rotationRate.x,      d.rotationRate.y,      d.rotationRate.z
            ])
            sampleCount += 1
            if buffer.count > windowSize {
                buffer.removeFirst(buffer.count - windowSize)
            }
            if sampleCount % hopSize == 0 && buffer.count == windowSize {
                classifyWindow()
            }
        }
    }

    func classifyWindow() {
        let N = Double(windowSize)
        var accelVars = [Double](repeating:0, count:3)
        var gyroVars  = [Double](repeating:0, count:3)
        for i in 0..<3 {
            let a = buffer.map{$0[i]}
            let am = a.reduce(0,+)/N
            accelVars[i] = a.map{($0-am)*($0-am)}.reduce(0,+)/N

            let g = buffer.map{$0[i+3]}
            let gm = g.reduce(0,+)/N
            gyroVars[i] = g.map{($0-gm)*($0-gm)}.reduce(0,+)/N
        }
        let accelVarMean = accelVars.reduce(0,+)/3
        let gyroVarMean  = gyroVars.reduce(0,+)/3
        let ratio = gyroVarMean / max(accelVarMean, 1e-12)
        print("📊 ratio=\(ratio)")
        if ratio < ratioThreshold {
            pushResult(false)
            return
        }

        let mags    = buffer.map { sqrt($0[0]*$0[0]+$0[1]*$0[1]+$0[2]*$0[2]) }
        let magMean = mags.reduce(0,+)/N
        let magVar  = mags.map{($0-magMean)*($0-magMean)}.reduce(0,+)/N

        var feats = [Double]()
        for i in 0..<6 {
            let vals = buffer.map{$0[i]}
            let m    = vals.reduce(0,+)/N
            feats.append(m)
            feats.append(vals.map{($0-m)*($0-m)}.reduce(0,+)/N)
        }
        feats.append(magMean); feats.append(magVar)

        do {
            let out = try rfModel.prediction(
                ax_mean: feats[0],  ax_var: feats[1],
                ay_mean: feats[2],  ay_var: feats[3],
                az_mean: feats[4],  az_var: feats[5],
                gx_mean: feats[6],  gx_var: feats[7],
                gy_mean: feats[8],  gy_var: feats[9],
                gz_mean: feats[10], gz_var: feats[11],
                mag_mean: feats[12], mag_var: feats[13]
            )
            pushResult(out.isWithUser == 1)
            print("✅ RF:\(out.isWithUser)")
        } catch {
            print("❌ RF error: \(error)")
            resultText = "Error"
        }
    }

    private func pushResult(_ isWith: Bool) {
        lastResults.removeFirst()
        lastResults.append(isWith)
        resultText = (lastResults[0]==false && lastResults[1]==false)
                     ? "LEFT BEHIND"
                     : "WITH USER"
        // record instantaneous detection for sampling
        instantStates.append(resultText == "WITH USER")
    }

    // MARK: Proof generation

    func generateAndSendProof(nonce: Data) { /* unchanged */ }

    // MARK: 3-minute sampling

    private func sampleOnce() {
        // majority vote over last window
        let presentCount = instantStates.filter{ $0 }.count
        let absentCount  = instantStates.count - presentCount
        let sampleIsPresent = presentCount > absentCount
        samples.append(sampleIsPresent)
        print("📋 Window sample #\(samples.count):", sampleIsPresent ? "present" : "absent", "(with:\(presentCount), without:\(absentCount))")
        // clear for next window
        instantStates.removeAll()
    }

    private func startSampling() {
        samples.removeAll()
        finalText = ""
        samplingTimer?.invalidate()
        attendanceTimer?.invalidate()

        DispatchQueue.main.asyncAfter(deadline: .now()+firstSampleDelay) {
            sampleOnce()
            samplingTimer = Timer.scheduledTimer(withTimeInterval: samplingInterval,
                                                 repeats: true) { _ in
                sampleOnce()
            }
        }

        attendanceTimer = Timer.scheduledTimer(withTimeInterval: attendanceWindow,
                                               repeats: false) { _ in
            samplingTimer?.invalidate()
            let presentCount = samples.filter{ $0 }.count
            let absentCount  = samples.count - presentCount
            let result = presentCount > absentCount
                       ? "✅ Attendance confirmed!"
                       : "❌ Attendance absent"
            finalText = result
            print("📊 Final: present \(presentCount) vs absent \(absentCount) →", result)
            session.recordAttendance(status: result)
        }
    }
}
