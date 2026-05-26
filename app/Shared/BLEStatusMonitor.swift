import Foundation
import CoreBluetooth

protocol BLEStatusMonitorDelegate: AnyObject {
    func monitorDidConnect(_ monitor: BLEStatusMonitor)
    func monitorDidDisconnect(_ monitor: BLEStatusMonitor)
    func monitor(_ monitor: BLEStatusMonitor, didReceive snapshot: StatusSnapshot)
}

final class BLEStatusMonitor: NSObject {
    weak var delegate: BLEStatusMonitorDelegate?
    private(set) var isConnected = false

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    static func displayName(for agentID: String) -> String {
        switch agentID.lowercased() {
        case "claude": return "Claude"
        case "codex": return "Codex"
        default: return agentID.capitalized
        }
    }

    private func notify(data: Data?) {
        if let data,
           let snapshot = try? JSONDecoder().decode(StatusSnapshot.self, from: data) {
            delegate?.monitor(self, didReceive: snapshot)
            return
        }
        let legacyStatus = AgentStatus.from(data: data)
        delegate?.monitor(self, didReceive: StatusSnapshot(
            version: 1,
            agents: ["claude": legacyStatus],
            quotas: nil,
            codexQuota: nil
        ))
    }
}

extension BLEStatusMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [bleServiceUUID], options: nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        delegate?.monitorDidConnect(self)
        peripheral.discoverServices([bleServiceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        isConnected = false
        delegate?.monitorDidDisconnect(self)
        central.scanForPeripherals(withServices: [bleServiceUUID], options: nil)
    }
}

extension BLEStatusMonitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == bleServiceUUID {
            peripheral.discoverCharacteristics([bleCharacteristicUUID], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let chars = service.characteristics else { return }
        for characteristic in chars where characteristic.uuid == bleCharacteristicUUID {
            peripheral.setNotifyValue(true, for: characteristic)
            peripheral.readValue(for: characteristic)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == bleCharacteristicUUID else { return }
        notify(data: characteristic.value)
    }
}
