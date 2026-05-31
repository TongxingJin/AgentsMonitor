import Foundation

struct TransportStatus: Identifiable, Equatable {
    enum State: Equatable {
        case connected
        case disconnected
        case unavailable
    }

    let id: String
    let name: String
    let state: State
}

final class StatusAggregator: NSObject {
    weak var delegate: StatusMonitorDelegate?

    var isConnected: Bool {
        bleMonitor.isConnected || usbMonitor.isConnected
            || tailscaleMonitors.contains { $0.isConnected }
    }

    static func displayName(for agentID: String) -> String {
        BLEStatusMonitor.displayName(for: agentID)
    }

    var transportStatuses: [TransportStatus] {
        var statuses: [TransportStatus] = [
            TransportStatus(id: "ble", name: "BLE", state: bleMonitor.isConnected ? .connected : .disconnected),
            TransportStatus(id: "usb", name: "USB", state: usbMonitor.isConnected ? .connected : .disconnected),
        ]

        let tailscaleState: TransportStatus.State
        if tailscaleMonitors.isEmpty {
            tailscaleState = .unavailable
        } else if tailscaleMonitors.contains(where: { $0.isConnected }) {
            tailscaleState = .connected
        } else {
            tailscaleState = .disconnected
        }
        statuses.append(TransportStatus(id: "tailscale", name: "Tailscale", state: tailscaleState))
        return statuses
    }

    private let bleMonitor = BLEStatusMonitor()
    private let usbMonitor = USBStatusMonitor()
    private var tailscaleMonitors: [TailscaleStatusMonitor] = []
    private var tailscaleProxies: [SourceProxy] = []
    private var snapshotBySource: [String: StatusSnapshot] = [:]
    private var sourceRecency: [String] = []

    // Per-agent status tracking: sourceID -> agentID -> (status, lastChangedAt)
    private var agentStatusBySource: [String: [String: (status: AgentStatus, date: Date)]] = [:]

    private lazy var bleProxy = SourceProxy(sourceID: "ble", aggregator: self)
    private lazy var usbProxy = SourceProxy(sourceID: "usb", aggregator: self)

    override init() {
        super.init()
        bleMonitor.delegate = bleProxy
        usbMonitor.delegate = usbProxy
    }

    func setTailscaleHosts(_ hosts: [String]) {
        tailscaleMonitors.forEach { $0.stop() }
        tailscaleMonitors = []
        tailscaleProxies = []
        snapshotBySource = snapshotBySource.filter { !$0.key.hasPrefix("tailscale:") }
        sourceRecency.removeAll { $0.hasPrefix("tailscale:") }

        for host in hosts where !host.isEmpty {
            let sourceID = "tailscale:\(host)"
            let monitor = TailscaleStatusMonitor(host: host)
            let proxy = SourceProxy(sourceID: sourceID, aggregator: self)
            monitor.delegate = proxy
            monitor.start()
            tailscaleMonitors.append(monitor)
            tailscaleProxies.append(proxy)
        }
    }

    fileprivate func received(_ snapshot: StatusSnapshot, from sourceID: String) {
        snapshotBySource[sourceID] = snapshot
        sourceRecency.removeAll { $0 == sourceID }
        sourceRecency.append(sourceID)

        var sourceMap = agentStatusBySource[sourceID] ?? [:]
        let now = Date()
        for (agentID, newStatus) in snapshot.agents {
            if let previous = sourceMap[agentID] {
                if previous.status != newStatus {
                    sourceMap[agentID] = (newStatus, now)
                }
            } else {
                // First report from this source: use distantPast so existing data wins
                sourceMap[agentID] = (newStatus, .distantPast)
            }
        }
        agentStatusBySource[sourceID] = sourceMap

        delegate?.monitorDidReceive(merged())
    }

    fileprivate func disconnected(from sourceID: String) {
        snapshotBySource.removeValue(forKey: sourceID)
        sourceRecency.removeAll { $0 == sourceID }
        agentStatusBySource.removeValue(forKey: sourceID)
        if !isConnected {
            delegate?.monitorDidDisconnect()
        } else {
            delegate?.monitorDidReceive(merged())
        }
    }

    private func merged() -> StatusSnapshot {
        // For each agent, use the status with the most recent change timestamp across all sources
        var agentLatest: [String: (status: AgentStatus, date: Date)] = [:]
        for sourceMap in agentStatusBySource.values {
            for (agentID, entry) in sourceMap {
                if let current = agentLatest[agentID] {
                    if entry.date > current.date {
                        agentLatest[agentID] = entry
                    }
                } else {
                    agentLatest[agentID] = entry
                }
            }
        }
        let agents = agentLatest.mapValues { $0.status }

        var mergedQuotas: [String: ProviderQuotaSnapshot] = [:]
        for snapshot in snapshotBySource.values {
            guard let quotas = snapshot.quotas else { continue }
            for (agentID, quota) in quotas {
                if let existing = mergedQuotas[agentID] {
                    let oldTs = existing.quotaUpdatedAt ?? 0
                    let newTs = quota.quotaUpdatedAt ?? 0
                    if newTs >= oldTs {
                        mergedQuotas[agentID] = quota
                    }
                } else {
                    mergedQuotas[agentID] = quota
                }
            }
        }

        return StatusSnapshot(
            version: 1,
            agents: agents,
            quotas: mergedQuotas.isEmpty ? nil : mergedQuotas
        )
    }
}

private final class SourceProxy: NSObject, StatusMonitorDelegate {
    let sourceID: String
    weak var aggregator: StatusAggregator?

    init(sourceID: String, aggregator: StatusAggregator) {
        self.sourceID = sourceID
        self.aggregator = aggregator
    }

    func monitorDidConnect() {
        aggregator?.delegate?.monitorDidConnect()
    }

    func monitorDidDisconnect() {
        aggregator?.disconnected(from: sourceID)
    }

    func monitorDidReceive(_ snapshot: StatusSnapshot) {
        aggregator?.received(snapshot, from: sourceID)
    }
}
