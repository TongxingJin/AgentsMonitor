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
        QuotaSnapshot(
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
