import Foundation
import CoreBluetooth

private let serviceUUID = CBUUID(string: "A1B2C3D4-E5F6-47A1-9B2C-001122334455")
private let characteristicUUID = CBUUID(string: "A1B2C3D4-E5F6-47A1-9B2C-001122334466")

enum AgentStatus: String, Codable {
    case working = "working"
    case idle = "idle"
    case awaitingApproval = "awaiting_approval"

    static func from(raw: String) -> AgentStatus {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "working", "busy", "running":
            return .working
        case "awaiting_approval", "awaiting-approval", "approve", "approval", "waiting_approval":
            return .awaitingApproval
        default:
            return .idle
        }
    }
}

struct CodexQuota: Codable, Equatable {
    let fiveHourFraction: Double
    let weeklyFraction: Double
}

struct BroadcastQuota: Codable, Equatable {
    let fiveHourRemainingHours: Double
    let fiveHourCapacityHours: Double
    let sevenDayRemainingDays: Double
    let sevenDayCapacityDays: Double
}

struct StoredCodexQuota: Codable, Equatable {
    let fiveHourFraction: Double?
    let weeklyFraction: Double?
    let fiveHourRemainingHours: Double?
    let sevenDayRemainingDays: Double?
    let source: String?

    var legacyQuota: CodexQuota? {
        guard let fiveHourFraction, let weeklyFraction else {
            return nil
        }
        return CodexQuota(
            fiveHourFraction: fiveHourFraction,
            weeklyFraction: weeklyFraction
        )
    }

    var broadcastQuota: BroadcastQuota? {
        guard let fiveHourRemainingHours, let sevenDayRemainingDays else {
            return nil
        }
        return BroadcastQuota(
            fiveHourRemainingHours: fiveHourRemainingHours,
            fiveHourCapacityHours: 5.0,
            sevenDayRemainingDays: sevenDayRemainingDays,
            sevenDayCapacityDays: 7.0
        )
    }
}

struct AgentSnapshot: Codable, Equatable {
    let version: Int
    let agents: [String: AgentStatus]
    let quotas: BroadcastQuota?
    let codexQuota: CodexQuota?
}

struct AgentConfig {
    let id: String
    let statusFileEnvKey: String
    let defaultStatusFile: String
    let processPattern: String
}

final class StatusSource {
    private let config: AgentConfig
    private let statusFilePath: String

    init(config: AgentConfig) {
        self.config = config
        let rawPath = ProcessInfo.processInfo.environment[config.statusFileEnvKey] ?? config.defaultStatusFile
        self.statusFilePath = NSString(string: rawPath).expandingTildeInPath
    }

    var debugDescription: String {
        "\(config.id): \(statusFilePath)"
    }

    func currentStatus() -> AgentStatus {
        guard FileManager.default.fileExists(atPath: statusFilePath),
              let text = try? String(contentsOfFile: statusFilePath, encoding: .utf8)
        else {
            return isProcessRunning() ? .working : .idle
        }

        return AgentStatus.from(raw: text)
    }

    private func isProcessRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-if", config.processPattern]
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

final class MultiAgentStatusSource {
    private let sources: [String: StatusSource]
    private let codexQuotaFilePath: String

    init(configs: [AgentConfig]) {
        self.sources = Dictionary(uniqueKeysWithValues: configs.map { ($0.id, StatusSource(config: $0)) })
        self.codexQuotaFilePath = NSString(string: "~/.codex/agent-status/quota.json").expandingTildeInPath
    }

    var debugDescriptions: [String] {
        sources.values.map(\.debugDescription).sorted()
    }

    func snapshot() -> AgentSnapshot {
        let agents = sources.mapValues { $0.currentStatus() }
        let storedQuota = readStoredCodexQuota()
        return AgentSnapshot(
            version: 1,
            agents: agents,
            quotas: storedQuota?.broadcastQuota,
            codexQuota: storedQuota?.legacyQuota
        )
    }

    private func readStoredCodexQuota() -> StoredCodexQuota? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: codexQuotaFilePath)) else { return nil }
        if let storedQuota = try? JSONDecoder().decode(StoredCodexQuota.self, from: data) {
            return storedQuota
        }
        if let legacyQuota = try? JSONDecoder().decode(CodexQuota.self, from: data) {
            return StoredCodexQuota(
                fiveHourFraction: legacyQuota.fiveHourFraction,
                weeklyFraction: legacyQuota.weeklyFraction,
                fiveHourRemainingHours: nil,
                sevenDayRemainingDays: nil,
                source: "legacy-codex-quota"
            )
        }
        return nil
    }
}

final class BLEBeacon: NSObject, CBPeripheralManagerDelegate {
    private var manager: CBPeripheralManager!
    private var characteristic: CBMutableCharacteristic!
    private let source: MultiAgentStatusSource
    private var timer: Timer?
    private var lastSnapshot: AgentSnapshot?

    init(source: MultiAgentStatusSource) {
        self.source = source
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            setupService()
            startAdvertising()
            startPolling()
        case .unauthorized:
            print("Bluetooth unauthorized. Grant access in System Settings -> Privacy -> Bluetooth.")
        default:
            print("Bluetooth state: \(peripheral.state.rawValue)")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == characteristicUUID else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }

        request.value = payload(for: source.snapshot())
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        push(source.snapshot(), force: true)
    }

    private func setupService() {
        characteristic = CBMutableCharacteristic(
            type: characteristicUUID,
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )

        let service = CBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        manager.add(service)
    }

    private func startAdvertising() {
        manager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "AgentStatus",
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ])
        print("BLE advertising as 'AgentStatus'")
    }

    private func startPolling() {
        timer?.invalidate()
        push(source.snapshot())
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.push(self.source.snapshot())
        }
    }

    private func push(_ snapshot: AgentSnapshot, force: Bool = false) {
        guard force || snapshot != lastSnapshot else {
            return
        }

        lastSnapshot = snapshot
        let data = payload(for: snapshot)
        manager.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
        print("[\(timestamp())] Status -> \(render(snapshot: snapshot))")
    }

    private func payload(for snapshot: AgentSnapshot) -> Data {
        (try? JSONEncoder().encode(snapshot)) ?? Data()
    }

    private func render(snapshot: AgentSnapshot) -> String {
        let statuses = snapshot.agents.keys.sorted()
            .map { "\($0)=\(snapshot.agents[$0]!.rawValue)" }
            .joined(separator: ", ")

        if let quota = snapshot.codexQuota {
            return statuses + String(
                format: " | 5h=%.0f%% weekly=%.0f%%",
                quota.fiveHourFraction * 100,
                quota.weeklyFraction * 100
            )
        }

        return statuses
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}

let configs = [
    AgentConfig(
        id: "claude",
        statusFileEnvKey: "CLAUDE_STATUS_FILE",
        defaultStatusFile: "~/.claude-status",
        processPattern: "claude"
    ),
    AgentConfig(
        id: "codex",
        statusFileEnvKey: "CODEX_STATUS_FILE",
        defaultStatusFile: "~/.codex/agent-status/status.txt",
        processPattern: "codex"
    )
]

let source = MultiAgentStatusSource(configs: configs)
let beacon = BLEBeacon(source: source)

print("AgentStatusBeacon started")
for line in source.debugDescriptions {
    print("Status file : \(line)")
}
print("Press Ctrl+C to stop.\n")

RunLoop.main.run()
