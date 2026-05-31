import Foundation
import CoreBluetooth

protocol StatusMonitorDelegate: AnyObject {
    func monitorDidConnect()
    func monitorDidDisconnect()
    func monitorDidReceive(_ snapshot: StatusSnapshot)
}

final class BLEStatusMonitor: NSObject {
    weak var delegate: StatusMonitorDelegate?
    private(set) var isConnected = false

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var statusCharacteristic: CBCharacteristic?
    private var pollTimer: Timer?

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
            delegate?.monitorDidReceive(snapshot)
            return
        }

        // Keep supporting very old plain-text beacons, but never downgrade to
        // unknown on malformed/truncated JSON payloads.
        guard let legacyStatus = data.flatMap({ AgentStatus.from(data: $0) }),
              legacyStatus != .unknown else {
            return
        }
        delegate?.monitorDidReceive(StatusSnapshot(version: 1, agents: ["claude": legacyStatus], quotas: nil))
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self,
                  let p = self.peripheral,
                  let c = self.statusCharacteristic else { return }
            p.readValue(for: c)
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
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
        delegate?.monitorDidConnect()
        statusCharacteristic = nil
        stopPolling()
        peripheral.discoverServices([bleServiceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        isConnected = false
        statusCharacteristic = nil
        stopPolling()
        delegate?.monitorDidDisconnect()
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
            statusCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
            peripheral.readValue(for: characteristic)
            startPolling()
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
