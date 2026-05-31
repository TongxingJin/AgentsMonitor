import Foundation

enum AgentStatus: String, Codable {
    case working
    case idle
    case awaitingApproval = "awaiting_approval"
    case unknown

    static func from(data: Data?) -> AgentStatus {
        guard let data else { return .unknown }

        if let snapshot = try? JSONDecoder().decode(StatusSnapshot.self, from: data),
           let firstStatus = snapshot.agents.values.first {
            return firstStatus
        }

        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .unknown
        }

        switch text.lowercased() {
        case "working", "busy", "running": return .working
        case "idle", "sleep": return .idle
        case "awaiting_approval", "awaiting-approval", "approve", "approval", "waiting_approval":
            return .awaitingApproval
        default: return .unknown
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

struct ProviderQuotaSnapshot: Codable {
    let fiveHourFraction: Double
    let weeklyFraction: Double
    let fiveHourRemainingHours: Double?
    let sevenDayRemainingDays: Double?
    let quotaUpdatedAt: Double?

    func asQuotaSnapshot() -> QuotaSnapshot {
        let fiveHourRemainingFraction = 1.0 - fiveHourFraction
        let sevenDayRemainingFraction = 1.0 - weeklyFraction
        return QuotaSnapshot(
            fiveHourFraction: max(0, min(1, fiveHourRemainingFraction)),
            sevenDayFraction: max(0, min(1, sevenDayRemainingFraction)),
            fiveHourRemainingHours: fiveHourRemainingHours,
            sevenDayRemainingDays: sevenDayRemainingDays
        )
    }
}

struct StatusSnapshot: Codable {
    let version: Int
    let agents: [String: AgentStatus]
    let quotas: [String: ProviderQuotaSnapshot]?
}
