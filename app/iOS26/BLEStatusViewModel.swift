import Foundation
import Combine

final class BLEStatusViewModel: NSObject, ObservableObject {
    @Published var statuses: [String: AgentStatus] = [:]
    @Published var availableAgents: [String] = []
    @Published var selectedAgentID = "codex"
    @Published var isConnected = false
    @Published private var claudeQuota: QuotaSnapshot = .fallback
    @Published private var codexQuota: QuotaSnapshot = .fallback

    var quotas: QuotaSnapshot {
        selectedAgentID == "codex" ? codexQuota : claudeQuota
    }
    @Published var transportStatuses: [TransportStatus] = []

    private let monitor = StatusAggregator()
    private static let hostsKey = "tailscaleHosts"

    var tailscaleHosts: [String] {
        (UserDefaults.standard.string(forKey: Self.hostsKey) ?? "")
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    override init() {
        super.init()
        monitor.delegate = self
        monitor.setTailscaleHosts(tailscaleHosts)
        syncTransportStatuses()
    }

    func applyTailscaleHosts(_ hosts: [String]) {
        UserDefaults.standard.set(hosts.joined(separator: "\n"), forKey: Self.hostsKey)
        monitor.setTailscaleHosts(hosts)
        syncTransportStatuses()
    }

    var currentStatus: AgentStatus {
        statuses[selectedAgentID] ?? .idle
    }

    var selectedAgentName: String {
        StatusAggregator.displayName(for: selectedAgentID)
    }

    func selectAgent(_ id: String) {
        selectedAgentID = id
    }

    private func syncTransportStatuses() {
        transportStatuses = monitor.transportStatuses
    }
}

extension BLEStatusViewModel: StatusMonitorDelegate {
    func monitorDidConnect() {
        isConnected = true
        syncTransportStatuses()
    }

    func monitorDidDisconnect() {
        isConnected = false
        statuses = [:]
        availableAgents = []
        claudeQuota = .fallback
        codexQuota = .fallback
        syncTransportStatuses()
    }

    func monitorDidReceive(_ snapshot: StatusSnapshot) {
        statuses = snapshot.agents

        let order = ["codex", "claude"]
        availableAgents = snapshot.agents.keys.sorted {
            let i0 = order.firstIndex(of: $0) ?? Int.max
            let i1 = order.firstIndex(of: $1) ?? Int.max
            return i0 < i1
        }

        claudeQuota = snapshot.quotas?.asQuotaSnapshot() ?? .fallback
        codexQuota = snapshot.codexQuota?.asQuotaSnapshot() ?? .fallback

        if !availableAgents.contains(selectedAgentID), let first = availableAgents.first {
            selectedAgentID = first
        }

        syncTransportStatuses()
    }
}
