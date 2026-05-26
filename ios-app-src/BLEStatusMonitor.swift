import Foundation
import CoreBluetooth
import Combine

enum AgentStatus: String, Codable {
    case working
    case idle
    case awaitingApproval = "awaiting_approval"
    case unknown

    static func from(data: Data?) -> AgentStatus {
        guard let data else {
            return .unknown
        }

        if let snapshot = try? JSONDecoder().decode(StatusSnapshot.self, from: data),
           let firstStatus = snapshot.agents.values.first {
            return firstStatus
        }

        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .unknown
        }

        switch text.lowercased() {
        case "working", "busy", "running":
            return .working
        case "idle", "sleep":
            return .idle
        case "awaiting_approval", "awaiting-approval", "approve", "approval", "waiting_approval":
            return .awaitingApproval
        default:
            return .unknown
        }
    }
}

struct QuotaSnapshot: Equatable {
    let fiveHourFraction: Double
    let sevenDayFraction: Double
    let fiveHourRemainingHours: Double?
    let sevenDayRemainingDays: Double?

    static let fallback = QuotaSnapshot(
        fiveHourFraction: 0,
        sevenDayFraction: 0,
        fiveHourRemainingHours: nil,
        sevenDayRemainingDays: nil
    )
}

struct BroadcastQuotaSnapshot: Codable {
    let fiveHourRemainingHours: Double
    let fiveHourCapacityHours: Double
    let sevenDayRemainingDays: Double
    let sevenDayCapacityDays: Double

    func asQuotaSnapshot() -> QuotaSnapshot {
        QuotaSnapshot(
            fiveHourFraction: fiveHourRemainingHours / max(fiveHourCapacityHours, 0.1),
            sevenDayFraction: sevenDayRemainingDays / max(sevenDayCapacityDays, 0.1),
            fiveHourRemainingHours: fiveHourRemainingHours,
            sevenDayRemainingDays: sevenDayRemainingDays
        )
    }
}

struct LegacyCodexQuotaSnapshot: Codable {
    let fiveHourFraction: Double
    let weeklyFraction: Double

    func asQuotaSnapshot() -> QuotaSnapshot {
        return QuotaSnapshot(
            fiveHourFraction: max(0, min(1, fiveHourFraction)),
            sevenDayFraction: max(0, min(1, weeklyFraction)),
            fiveHourRemainingHours: nil,
            sevenDayRemainingDays: nil
        )
    }
}

struct StatusSnapshot: Codable {
    let version: Int
    let agents: [String: AgentStatus]
    let quotas: BroadcastQuotaSnapshot?
    let codexQuota: LegacyCodexQuotaSnapshot?
}

final class BLEStatusMonitor: NSObject, ObservableObject {
    @Published var statuses: [String: AgentStatus] = [:]
    @Published var availableAgents: [String] = []
    @Published var selectedAgentID = "codex"
    @Published var isConnected = false
    @Published var quotas: QuotaSnapshot = .fallback

    private let serviceUUID = CBUUID(string: "A1B2C3D4-E5F6-47A1-9B2C-001122334455")
    private let characteristicUUID = CBUUID(string: "A1B2C3D4-E5F6-47A1-9B2C-001122334466")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?

    var currentStatus: AgentStatus {
        statuses[selectedAgentID] ?? .unknown
    }

    var selectedAgentName: String {
        Self.displayName(for: selectedAgentID)
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func selectAgent(_ id: String) {
        selectedAgentID = id
    }

    static func displayName(for agentID: String) -> String {
        switch agentID.lowercased() {
        case "claude":
            return "Claude"
        case "codex":
            return "Codex"
        default:
            return agentID.capitalized
        }
    }

    private func updateStatuses(from data: Data?) {
        if let data,
           let snapshot = try? JSONDecoder().decode(StatusSnapshot.self, from: data) {
            statuses = snapshot.agents
            let order = ["codex", "claude"]
            availableAgents = snapshot.agents.keys.sorted {
                let i0 = order.firstIndex(of: $0) ?? Int.max
                let i1 = order.firstIndex(of: $1) ?? Int.max
                return i0 < i1
            }
            quotas = snapshot.quotas?.asQuotaSnapshot()
                ?? snapshot.codexQuota?.asQuotaSnapshot()
                ?? .fallback

            if !availableAgents.contains(selectedAgentID), let first = availableAgents.first {
                selectedAgentID = first
            }
            return
        }

        let legacyStatus = AgentStatus.from(data: data)
        statuses = ["claude": legacyStatus]
        availableAgents = ["claude"]
        quotas = .fallback
        if selectedAgentID != "claude" {
            selectedAgentID = "claude"
        }
    }
}

extension BLEStatusMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            isConnected = false
            return
        }
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
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
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        statuses = [:]
        availableAgents = []
        quotas = .fallback
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }
}

extension BLEStatusMonitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
            return
        }

        for service in services where service.uuid == serviceUUID {
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let chars = service.characteristics else {
            return
        }

        for characteristic in chars where characteristic.uuid == characteristicUUID {
            peripheral.setNotifyValue(true, for: characteristic)
            peripheral.readValue(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == characteristicUUID else {
            return
        }

        updateStatuses(from: characteristic.value)
    }
}
