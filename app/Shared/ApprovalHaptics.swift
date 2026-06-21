import Foundation
import AudioToolbox
#if canImport(UIKit)
import UIKit
#endif

final class ApprovalHaptics {
    static let shared = ApprovalHaptics()

    private var lastTriggerAt: TimeInterval = 0
    private let cooldown: TimeInterval = 1.5

    private init() {}

    func triggerIfNeeded() {
        let now = Date().timeIntervalSince1970
        guard now - lastTriggerAt >= cooldown else { return }
        lastTriggerAt = now

        #if canImport(UIKit)
        let warning = UINotificationFeedbackGenerator()
        warning.prepare()
        warning.notificationOccurred(.warning)

        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.prepare()
        impact.impactOccurred()
        #endif

        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}
