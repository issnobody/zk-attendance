import SwiftUI
import CoreMotion
import CoreML
import Combine
import AnyCodable


let proveURL  = URL(string: "http://192.168.100.88:5100/prove")!
let verifyURL = URL(string: "http://192.168.100.88:5100/verify")!


struct ContentView: View {
    // MARK: Presence detection
        private let motion = CMMotionManager()
        @State private var buffer: [[Double]] = []
        @State private var sampleCount = 0
        @State private var resultText = "Idle"
        @State private var lastResults: [Bool] = [true, true]
        @State private var instantStates: [Bool] = []


        // MARK: Proof UI state
        @State private var proofResult: String = ""
        @State private var lastSentNonce: Data? = nil

        // MARK: Out‐of‐range detection
        @State private var lastBeaconTime = Date()
        @State private var outOfRange = false
        private let rangeThreshold: TimeInterval = 35
        private let rangeTimer = Timer.publish(every: 1, on: .main, in: .common)
                                     .autoconnect()

        // MARK: 3-minute attendance sampling
        @State private var samples: [Bool] = []
        @State private var finalAttendance: String = ""
        @State private var samplingTimer: Timer?
        @State private var attendanceTimer: Timer?
        private let samplingInterval: TimeInterval = 20
        private let attendanceWindow: TimeInterval = 180

        // MARK: BLE scanner
        @StateObject private var scanner = BLEScanner()

        // MARK: RF model
        private let rfModel: PresenceRF = {
            let cfg = MLModelConfiguration()
            return try! PresenceRF(configuration: cfg)
        }()

        // MARK: Sliding‐window params
        private let windowSize = 100   // 2 s @ 50 Hz
        private let hopSize    = 50    // 1 s @ 50 Hz
        private let ratioThreshold: Double = 5.0

        var body: some View {
            VStack(spacing: 16) {
                Text("ProverApp Sliding + Proof")
                    .font(.headline)

                // ─── Instantaneous state ───
                Text(resultText)
                    .font(.largeTitle)
                    .foregroundColor(resultText == "WITH USER" ? .green : .red)

                // ─── In/Out of range ───
                Text(outOfRange ? "OUT OF RANGE" : "IN RANGE")
                    .font(.subheadline)
                    .foregroundColor(outOfRange ? .orange : .secondary)

                // ─── Final attendance after 3 min ───
                if !finalAttendance.isEmpty {
                    Text(finalAttendance)
                        .font(.title2)
                        .foregroundColor(finalAttendance.hasPrefix("✅") ? .green : .red)
                }

                Button("Start Capture & Scan") {
                    startContinuousCapture()
                    scanner.start()
                    lastBeaconTime = Date()
                    startSampling()
                }
                .padding(.top)

                Text(proofResult)
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            .padding()
            // ─── Update out‐of‐range every second ───
            .onReceive(rangeTimer) { _ in
                let elapsed = Date().timeIntervalSince(lastBeaconTime)
                outOfRange = (elapsed > rangeThreshold)
            }
            // ─── On each new beacon nonce ───
            .onReceive(scanner.noncePublisher) { nonce in
                lastBeaconTime = Date()
                guard resultText == "WITH USER", nonce != lastSentNonce else { return }
                lastSentNonce = nonce
                let hex = nonce.map { String(format: "%02x", $0) }.joined()
                print("🔑 Ranged nonce:", hex)
                proofResult = "Generating proof…"
                generateAndSendProof(nonce: nonce)
            }
            .onAppear {
                print("ProverApp ready")
            }
        }

        // MARK: Capture & classify (unchanged)
        func startContinuousCapture() {
            buffer.removeAll()
            sampleCount = 0
            lastResults = [true, true]
            resultText = "Capturing…"

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
                let a = buffer.map { $0[i] }
                let am = a.reduce(0,+)/N
                accelVars[i] = a.map { ($0-am)*($0-am) }.reduce(0,+)/N

                let g = buffer.map { $0[i+3] }
                let gm = g.reduce(0,+)/N
                gyroVars[i] = g.map { ($0-gm)*($0-gm) }.reduce(0,+)/N
            }
            let accelVarMean = accelVars.reduce(0,+)/3
            let gyroVarMean  = gyroVars.reduce(0,+)/3
            let ratio = gyroVarMean / max(accelVarMean,1e-12)
            print("📊 ratio=\(ratio)")
            if ratio < ratioThreshold {
                pushResult(false); return
            }

            // Fallback RF
            let mags    = buffer.map {
                sqrt($0[0]*$0[0] + $0[1]*$0[1] + $0[2]*$0[2])
            }
            let magMean = mags.reduce(0,+)/N
            let magVar  = mags.map { ($0-magMean)*($0-magMean) }.reduce(0,+)/N

            var feats = [Double]()
            for i in 0..<6 {
                let vals = buffer.map { $0[i] }
                let m    = vals.reduce(0,+)/N
                feats.append(m)
                feats.append(vals.map { ($0-m)*($0-m) }.reduce(0,+)/N)
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
                print("✅ RF:", out.isWithUser)
            } catch {
                print("❌ RF error:", error)
                resultText = "Error"
            }
        }

        private func pushResult(_ isWith: Bool) {
            lastResults.removeFirst()
            lastResults.append(isWith)
            resultText = (lastResults[0]==false && lastResults[1]==false)
                         ? "LEFT BEHIND" : "WITH USER"
        }
    private func sampleOnce() {
        // Count how many “with user” vs “left behind” in the last window
        let presentCount = instantStates.filter{ $0 }.count
        let absentCount  = instantStates.count - presentCount

        // Decide this sample
        let sampleIsPresent = presentCount > absentCount
        samples.append(sampleIsPresent)
        print("📋 Window sample #\(samples.count):",
              sampleIsPresent ? "present" : "absent",
              "(with:\(presentCount), without:\(absentCount))")

        // Clear buffer for next window
        instantStates.removeAll()

    }

        // MARK: 3-minute sampling
    private func startSampling() {
        // 1) Reset state
            samples.removeAll()
            finalAttendance = ""
            samplingTimer?.invalidate()
            attendanceTimer?.invalidate()

            // 2) Schedule first sample after a 5 s delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                self.sampleOnce()  // sample #1 at t=5s

                // 3) Now set up regular 40 s sampling
                self.samplingTimer = Timer.scheduledTimer(withTimeInterval: self.samplingInterval,
                                                          repeats: true) { _ in
                    self.sampleOnce()
                }
            }

            // 4) After 3 min total, stop sampling and make the final call
            attendanceTimer = Timer.scheduledTimer(withTimeInterval: attendanceWindow,
                                                   repeats: false) { _ in
                self.samplingTimer?.invalidate()
                let presentCount = self.samples.filter{ $0 }.count
                let absentCount  = self.samples.count - presentCount
                let result = presentCount > absentCount
                    ? "✅ Attendance confirmed!"
                    : "❌ Attendance absent"
                self.finalAttendance = result
                print("📊 Final (present \(presentCount) vs absent \(absentCount)) →", result)
                
                // save to history if you’re doing that:
                // session.addRecord(AttendanceRecord(status: result))
            }
    }


    func generateAndSendProof(nonce: Data) {
        
        // 1️⃣ Hex‐encode the 8‐byte nonce
        let nonceHex = nonce.map { String(format: "%02x", $0) }.joined()
        print("🔑 Sending /prove nonceHex:", nonceHex)
        
        // 2️⃣ Build the /prove request
        var req1 = URLRequest(url: proveURL)
        req1.httpMethod = "POST"
        req1.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req1.httpBody = try? JSONEncoder().encode(["nonceHex": nonceHex])
        
        // 3️⃣ Fire off /prove
        URLSession.shared.dataTask(with: req1) { data, resp, err in
            if let err = err {
                DispatchQueue.main.async {
                    self.proofResult = "❌ Prove HTTP error: \(err.localizedDescription)"
                }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    self.proofResult = "❌ No data from /prove"
                }
                return
            }
            
            // 4️⃣ Decode the ProveResponse
            do {
                let resp1 = try JSONDecoder().decode(ProveResponse.self, from: data)
                // unwrap AnyCodable → native types
                let proof   = resp1.proof.mapValues { $0.value }
                let signals = resp1.publicSignals.map { $0.value }
                
                // 5️⃣ Build & fire the /verify request
                var req2 = URLRequest(url: verifyURL)
                req2.httpMethod = "POST"
                req2.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String:Any] = [
                    "proof": proof,
                    "publicSignals": signals
                ]
                req2.httpBody = try? JSONSerialization.data(withJSONObject: body)
                
                // 6️⃣ Handle the /verify response and update the UI
                URLSession.shared.dataTask(with: req2) { data2, resp2, err2 in
                    DispatchQueue.main.async {
                        if let err2 = err2 {
                            // network or server‐down error
                            self.proofResult = "❌ Verify error: \(err2.localizedDescription)"
                        }
                        else if let data2 = data2,
                                let json = try? JSONDecoder()
                            .decode([String:Bool].self, from: data2),
                                let ok = json["verified"] {
                            // server responded with { verified: true/false }
                            self.proofResult = ok
                            ? "✅ Attendance confirmed!"
                            : "❌ Invalid proof"
                        } else {
                            // malformed JSON or missing "verified" field
                            self.proofResult = "❌ Bad verify response"
                        }
                    }
                }.resume()
                
            } catch {
                DispatchQueue.main.async {
                    self.proofResult = "❌ Decode /prove error: \(error.localizedDescription)"
                }
            }
            
        }.resume()
    }

    // Helper to send the proof to /verify
    func verifyOnServer(proof: [String:Any], publicSignals: [Any]) {
        var req2 = URLRequest(url: URL(string: "http://192.168.1.199:5100/verify")!)
        req2.httpMethod = "POST"
        req2.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req2.httpBody = try? JSONSerialization.data(withJSONObject: [
            "proof": proof,
            "publicSignals": publicSignals
        ])
        
        URLSession.shared.dataTask(with: req2) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.proofResult = "❌ Verify error: \(error.localizedDescription)"
                } else {
                    self.proofResult = "✅ Proof sent!"
                }
            }
        }.resume()
    }

}
