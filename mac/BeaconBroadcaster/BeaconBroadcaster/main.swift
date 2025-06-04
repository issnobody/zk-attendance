import Foundation
import CoreLocation
import CoreBluetooth

// 1) Fixed UUID prefix (first 16 bytes must match your scanner)
let fixedUUID = UUID(uuidString: "D4F56A24-9CDE-4B12-ABCD-1234567890AB")!
let beaconIdentifier = "com.example.zk-attendance"

final class BeaconBroadcaster: NSObject {
    private var peripheralManager: CBPeripheralManager!
    private var timer: Timer!

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
}

extension BeaconBroadcaster: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else {
            print("⚠️ Bluetooth not ready (\(peripheral.state.rawValue))")
            return
        }
        // first advertise immediately
        rotateAndAdvertise()
        // then every 30 seconds
        timer = Timer.scheduledTimer(
            timeInterval: 30,
            target: self,
            selector: #selector(rotateAndAdvertise),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func rotateAndAdvertise() {
        // generate an 8‑byte nonce
        var nonce = [UInt8](repeating: 0, count: 8)
        let status = SecRandomCopyBytes(kSecRandomDefault, nonce.count, &nonce)
        guard status == errSecSuccess else {
            print("💀 Failed to generate nonce"); exit(EXIT_FAILURE)
        }

        // split into Major/Minor for iBeacon
        let major = UInt16(nonce[0]) << 8 | UInt16(nonce[1])
        let minor = UInt16(nonce[2]) << 8 | UInt16(nonce[3])

        // build the beacon region
        let region = CLBeaconRegion(
            uuid: fixedUUID,
            major: major,
            minor: minor,
            identifier: beaconIdentifier
        )
        // get its advertisement dictionary
        var advData = region.peripheralData(withMeasuredPower: nil) as! [String:Any]
        // add a friendly local name
        advData[CBAdvertisementDataLocalNameKey] = "ZK-Attendance"

        // restart advertising
        peripheralManager.stopAdvertising()
        peripheralManager.startAdvertising(advData)

        // log what we sent
        let hex = nonce.map { String(format: "%02x", $0) }.joined()
        print("➡️ Advertising nonce:", hex,
              "Major:", major, "Minor:", minor)
    }
}

// entrypoint
print("🔍 Starting BeaconBroadcaster…")
let broadcaster = BeaconBroadcaster()
RunLoop.main.run()
