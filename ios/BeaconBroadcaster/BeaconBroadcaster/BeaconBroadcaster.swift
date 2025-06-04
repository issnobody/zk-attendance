import Foundation
import CoreBluetooth
import Security
import Combine

final class BeaconBroadcaster: NSObject,
                              CBPeripheralManagerDelegate,
                              ObservableObject
{
    private var pm: CBPeripheralManager!
    /// Base UUID with a fixed first 8 bytes; last 8 bytes will hold our nonce.
    private let baseUuidString = "D4F56A24-9CDE-4B12-ABCD-000000000000"

    override init() {
        super.init()
        pm = CBPeripheralManager(delegate: self, queue: nil)
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else { return }
        advertise()
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            self.advertise()
        }
    }

    private func advertise() {
        // 1) Generate 8-byte random nonce
        var nonce = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, nonce.count, &nonce)

        // 2) Build the full 16-byte UUID
        //    by replacing the last 8 bytes of the base with our nonce.
        var uuidBytes = [UInt8](repeating: 0, count: 16)
        // parse base UUID
        let baseUUID = UUID(uuidString: baseUuidString)!
        withUnsafeBytes(of: baseUUID.uuid) { buf in
            for i in 0..<16 { uuidBytes[i] = buf[i] }
        }
        // overwrite last 8 bytes
        for i in 0..<8 { uuidBytes[8 + i] = nonce[i] }
        // rebuild
        let dynamicUUID = UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
        let serviceUUID = CBUUID(string: dynamicUUID.uuidString)

        // 3) Assemble advertisement data
        let adv: [String:Any] = [
            CBAdvertisementDataServiceUUIDsKey:      [serviceUUID],
            CBAdvertisementDataLocalNameKey:         "ZK-Attendance"
        ]

        // 4) Restart advertising
        pm.stopAdvertising()
        pm.startAdvertising(adv)

        // 5) Debug
        let hex = nonce.map { String(format:"%02x",$0) }.joined()
        print("➡️ Advertising nonce:", hex,
              "→ Service UUID:", dynamicUUID.uuidString)
    }
}
