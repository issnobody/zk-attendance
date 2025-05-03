import Foundation
import CoreBluetooth

// Early debug print
print("🔍 Starting BeaconBroadcaster…")

final class Beacon: NSObject, CBPeripheralManagerDelegate {
    private var pm: CBPeripheralManager!
    private var timer: Timer?
    private let uuid = CBUUID(string: "DEAD")

    override init() {
        super.init()
        print("🔍 Beacon instance created, initializing CBPeripheralManager")
        pm = CBPeripheralManager(delegate: self, queue: nil)
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        // Print raw state for debugging
        print("📶 CB state rawValue = \(peripheral.state.rawValue)")

        switch peripheral.state {
        case .poweredOn:
            print("📶 Powered On — starting to advertise")
            rotate(nil)
            // Schedule nonce rotation every 30 seconds
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true, block: rotate)

        case .unauthorized:
            print("⛔️ Bluetooth unauthorized. Add NSBluetoothAlwaysUsageDescription to your Info.plist.")
            exit(EXIT_FAILURE)

        case .poweredOff:
            print("🔇 Bluetooth is powered off. Turn it on in Control Center.")
            exit(EXIT_FAILURE)

        case .unsupported:
            print("⚠️ Bluetooth LE is not supported on this Mac.")
            exit(EXIT_FAILURE)

        default:
            print("⚠️ Unhandled CB state: \(peripheral.state)")
            exit(EXIT_FAILURE)
        }
    }

    @objc private func rotate(_ timer: Timer?) {
        // 1. Generate 8-byte random nonce
        var nonce = [UInt8](repeating: 0, count: 8)
        let status = SecRandomCopyBytes(kSecRandomDefault, nonce.count, &nonce)
        guard status == errSecSuccess else {
            print("💀 Failed to generate random bytes"); exit(EXIT_FAILURE)
        }
        let data = Data(nonce)
        let hex = data.map { String(format: "%02x", $0) }.joined()

        // 2. Build advertisement payload
        let adv: [String: Any] = [
            // still a CBUUID array here
            CBAdvertisementDataServiceUUIDsKey: [uuid],
            // but the inner dict must be [String: Data], not [CBUUID: Data]
            CBAdvertisementDataServiceDataKey: [uuid.uuidString: data]
        ]

        // 3. Restart advertising
        pm.stopAdvertising()
        pm.startAdvertising(adv)

        // 4. Debug print
        print("➡️  \(hex)")
    }

}

// Instantiate and enter the run loop
let beacon = Beacon()
print("🔍 Beacon instance created, about to enter dispatchMain()")
dispatchMain()
