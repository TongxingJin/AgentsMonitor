import Foundation
import Combine

final class BLEStatusViewModel: NSObject, ObservableObject {
    @Published var statuses: [String: AgentStatus] = [:]
    @Published var availableAgents: [String] = []
    @Published var selectedAgentID = "codex"
    @Published var isConnected = false
    @Published var quotas: QuotaSnapshot = .fallback

    private let monitor = BLEStatusMonitor()

    override init() {
        super.init()
        monitor.delegate = self
    }

    var currentStatus: AgentStatus {
        statuses[selectedAgentID] ?? .unknown
    }

    var selectedAgentName: String {
        BLEStatusMonitor.displayName(for: selectedAgentID)
    }

    func selectAgent(_ id: String) {
        selectedAgentID = id
    }
}

extension BLEStatusViewModel: BLEStatusMonitorDelegate {
    func monitorDidConnect(_ monitor: BLEStatusMonitor) {
        isConnected = true
    }

    func monitorDidDisconnect(_ monitor: BLEStatusMonitor) {
        isConnected = false
        statuses = [:]
        availableAgents = []
        quotas = .fallback
    }

    func monitor(_ monitor: BLEStatusMonitor, didReceive snapshot: StatusSnapshot) {
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
    }
}
