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
        bleMonitor.isConnected || httpMonitor.isConnected || usbMonitor.isConnected
            || tailscaleMonitors.contains { $0.isConnected }
    }

    static func displayName(for agentID: String) -> String {
        BLEStatusMonitor.displayName(for: agentID)
    }

    var transportStatuses: [TransportStatus] {
        var statuses: [TransportStatus] = [
            TransportStatus(id: "ble", name: "BLE", state: bleMonitor.isConnected ? .connected : .disconnected),
            TransportStatus(id: "lan", name: "局域网", state: httpMonitor.isConnected ? .connected : .disconnected),
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
    private let httpMonitor = HTTPStatusMonitor()
    private let usbMonitor = USBStatusMonitor()
    private var tailscaleMonitors: [TailscaleStatusMonitor] = []
    private var tailscaleProxies: [SourceProxy] = []
    private var snapshotBySource: [String: StatusSnapshot] = [:]

    private lazy var bleProxy = SourceProxy(sourceID: "ble", aggregator: self)
    private lazy var httpProxy = SourceProxy(sourceID: "http", aggregator: self)
    private lazy var usbProxy = SourceProxy(sourceID: "usb", aggregator: self)

    override init() {
        super.init()
        bleMonitor.delegate = bleProxy
        httpMonitor.delegate = httpProxy
        usbMonitor.delegate = usbProxy
    }

    func setTailscaleHosts(_ hosts: [String]) {
        tailscaleMonitors.forEach { $0.stop() }
        tailscaleMonitors = []
        tailscaleProxies = []
        snapshotBySource = snapshotBySource.filter { !$0.key.hasPrefix("tailscale:") }

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
        delegate?.monitorDidReceive(merged())
    }

    fileprivate func disconnected(from sourceID: String) {
        snapshotBySource.removeValue(forKey: sourceID)
        if !isConnected {
            delegate?.monitorDidDisconnect()
        } else {
            delegate?.monitorDidReceive(merged())
        }
    }

    private func merged() -> StatusSnapshot {
        var agents: [String: AgentStatus] = [:]
        for s in snapshotBySource.values {
            agents.merge(s.agents) { _, new in new }
        }
        let quotas = snapshotBySource.values.compactMap { $0.quotas }.first
        let codexQuota = snapshotBySource.values.compactMap { $0.codexQuota }.first
        return StatusSnapshot(version: 1, agents: agents, quotas: quotas, codexQuota: codexQuota)
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
