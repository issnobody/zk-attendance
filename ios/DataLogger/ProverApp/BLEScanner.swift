import Foundation
import CoreBluetooth
import Combine

/// Scans for any peripheral advertising
///    • Local Name = "ZK-Attendance"
///    • A 128-bit service UUID whose last 8 bytes are the nonce
class BLEScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    private var central: CBCentralManager!
    private let beaconName = "ZK-Attendance"
    private let basePrefix: [UInt8] = [ 0xD4,0xF5,0x6A,0x24, 0x9C,0xDE,0x4B,0x12 ]

    /// Emits the nonce only once per change
    let noncePublisher = PassthroughSubject<Data, Never>()

    /// Remember the last nonce we actually emitted
    private var lastSeenNonce: Data? = nil

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func start() {
        central.scanForPeripherals(
            withServices: nil,
            options: [ CBCentralManagerScanOptionAllowDuplicatesKey: true ]
        )
        print("🔍 BLEScanner: Started scanning")
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            print("⚠️ BLE not powered on:", central.state.rawValue)
            return
        }
        start()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String:Any],
        rssi RSSI: NSNumber
    ) {
        // 1) Filter on your Local Name
        guard let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
              name == beaconName else {
            return
        }

        // 2) Extract service UUIDs
        guard let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
              let first = uuids.first,
              let dynUUID = UUID(uuidString: first.uuidString)
        else { return }

        // 3) Turn that 128-bit UUID into raw bytes
        var raw = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: dynUUID.uuid) { buf in
            for i in 0..<16 { raw[i] = buf[i] }
        }

        // 4) Check your fixed 8-byte prefix
        guard raw[0..<8].elementsEqual(basePrefix) else { return }

        // 5) Slice off the last 8 bytes as nonce
        let nonceData = Data(raw[8..<16])

        // 6) Throttle duplicates: only emit when *different* from lastSeen
        if nonceData == lastSeenNonce {
            return
        }
        lastSeenNonce = nonceData

        // 7) Log & publish
        let hex = raw[8..<16].map { String(format:"%02x",$0) }.joined()
        print("🔑 BLEScanner extracted nonce:", hex)
        noncePublisher.send(nonceData)
    }
}
