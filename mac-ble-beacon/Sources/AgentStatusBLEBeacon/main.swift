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

struct ProviderQuota: Codable, Equatable {
    let fiveHourFraction: Double
    let weeklyFraction: Double
    let fiveHourRemainingHours: Double?
    let sevenDayRemainingDays: Double?
    let quotaUpdatedAt: Double?
}

struct StoredQuotaEnvelope: Codable, Equatable {
    let version: Int?
    let quotaUpdatedAt: Double?
    let codex: ProviderQuota?
    let claude: ProviderQuota?
    let codexError: String?
    let claudeError: String?
}

struct AgentSnapshot: Codable, Equatable {
    let version: Int
    let agents: [String: AgentStatus]
    let quotas: [String: ProviderQuota]?
}

struct WireProviderQuota: Codable, Equatable {
    let fiveHourFraction: Double
    let weeklyFraction: Double
    let fiveHourRemainingHours: Double?
    let sevenDayRemainingDays: Double?

    enum CodingKeys: String, CodingKey {
        case fiveHourFraction = "fh"
        case weeklyFraction = "wk"
        case fiveHourRemainingHours = "rh"
        case sevenDayRemainingDays = "rd"
    }
}

struct WireAgentSnapshot: Codable, Equatable {
    let version: Int
    let agents: [String: AgentStatus]
    let quotas: [String: WireProviderQuota]?

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case agents = "a"
        case quotas = "q"
    }
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
    private let quotaReaderPath: String
    private let quotaRefreshInterval: TimeInterval
    private var lastQuotaRefreshAt: Date?
    private var quotaRefreshRunning = false

    init(configs: [AgentConfig]) {
        self.sources = Dictionary(uniqueKeysWithValues: configs.map { ($0.id, StatusSource(config: $0)) })
        self.codexQuotaFilePath = NSString(string: "~/.codex/agent-status/quota.json").expandingTildeInPath
        self.quotaReaderPath = NSString(string: "~/.codex/agent-status-hooks/read_quota.py").expandingTildeInPath

        let raw = ProcessInfo.processInfo.environment["QUOTA_REFRESH_SECONDS"] ?? "300"
        let parsed = TimeInterval(raw) ?? 300
        // Keep a practical floor to avoid aggressive polling.
        self.quotaRefreshInterval = max(300, parsed)
    }

    var debugDescriptions: [String] {
        sources.values.map(\.debugDescription).sorted()
    }

    func snapshot() -> AgentSnapshot {
        maybeRefreshQuota()
        let agents = sources.mapValues { $0.currentStatus() }
        let storedQuotas = readStoredQuotas()
        return AgentSnapshot(
            version: 1,
            agents: agents,
            quotas: storedQuotas
        )
    }

    private func maybeRefreshQuota() {
        if quotaRefreshRunning {
            return
        }

        let now = Date()
        if let last = lastQuotaRefreshAt,
           now.timeIntervalSince(last) < quotaRefreshInterval {
            return
        }

        guard FileManager.default.fileExists(atPath: quotaReaderPath) else {
            return
        }

        quotaRefreshRunning = true
        lastQuotaRefreshAt = now

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            defer {
                DispatchQueue.main.async {
                    self.quotaRefreshRunning = false
                }
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", self.quotaReaderPath]
            process.environment = ProcessInfo.processInfo.environment
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // Keep beacon alive even if quota refresh fails.
            }
        }
    }

    private func readStoredQuotas() -> [String: ProviderQuota]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: codexQuotaFilePath)) else { return nil }
        guard let envelope = try? JSONDecoder().decode(StoredQuotaEnvelope.self, from: data) else {
            return nil
        }

        var quotas: [String: ProviderQuota] = [:]
        if let codex = envelope.codex {
            quotas["codex"] = codex
        }
        if let claude = envelope.claude {
            quotas["claude"] = claude
        }
        return quotas.isEmpty ? nil : quotas
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

        let data = payload(for: source.snapshot())
        print("[BLE] Read request offset=\(request.offset) totalBytes=\(data.count)")
        guard request.offset <= data.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = data.subdata(in: request.offset..<data.count)
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        print("[BLE] iOS subscribed, MTU=\(central.maximumUpdateValueLength)")
        push(source.snapshot(), force: true)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        print("[BLE] iOS unsubscribed")
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        print("[BLE] Ready to retry notify")
        if let last = lastSnapshot {
            push(last, force: true)
        }
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
        let sent = manager.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
        print("[\(timestamp())] Status -> \(render(snapshot: snapshot)) [notify:\(sent ? "ok" : "FAILED, \(data.count)bytes")]")
    }

    private func payload(for snapshot: AgentSnapshot) -> Data {
        var wireQuotas: [String: WireProviderQuota] = [:]
        if let quotas = snapshot.quotas {
            for (agentID, quota) in quotas {
                wireQuotas[agentID] = WireProviderQuota(
                    fiveHourFraction: quota.fiveHourFraction,
                    weeklyFraction: quota.weeklyFraction,
                    fiveHourRemainingHours: quota.fiveHourRemainingHours,
                    sevenDayRemainingDays: quota.sevenDayRemainingDays
                )
            }
        }

        let wireSnapshot = WireAgentSnapshot(
            version: snapshot.version,
            agents: snapshot.agents,
            quotas: wireQuotas.isEmpty ? nil : wireQuotas
        )
        return (try? JSONEncoder().encode(wireSnapshot)) ?? Data()
    }

    private func render(snapshot: AgentSnapshot) -> String {
        let statuses = snapshot.agents.keys.sorted()
            .map { "\($0)=\(snapshot.agents[$0]!.rawValue)" }
            .joined(separator: ", ")

        guard let quotas = snapshot.quotas else { return statuses }
        var segments: [String] = []
        if let codex = quotas["codex"] {
            segments.append(String(format: "codex 5h=%.0f%% weekly=%.0f%%", codex.fiveHourFraction * 100, codex.weeklyFraction * 100))
        }
        if let claude = quotas["claude"] {
            segments.append(String(format: "claude 5h=%.0f%% weekly=%.0f%%", claude.fiveHourFraction * 100, claude.weeklyFraction * 100))
        }
        if segments.isEmpty { return statuses }
        return statuses + " | " + segments.joined(separator: " | ")
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

print("AgentStatusBLEBeacon started")
for line in source.debugDescriptions {
    print("Status file : \(line)")
}
print("Press Ctrl+C to stop.\n")

RunLoop.main.run()
