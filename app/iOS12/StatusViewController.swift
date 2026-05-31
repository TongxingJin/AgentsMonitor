import UIKit

final class StatusViewController: UIViewController {
    private let monitor = StatusAggregator()

    private var statuses: [String: AgentStatus] = [:]
    private var availableAgents: [String] = []
    private var selectedAgentID = "codex"
    private var claudeQuota: QuotaSnapshot = .fallback
    private var codexQuota: QuotaSnapshot = .fallback
    private var quotas: QuotaSnapshot { selectedAgentID == "codex" ? codexQuota : claudeQuota }
    private var transportStatuses: [TransportStatus] = []
    private var renderedStatus: AgentStatus?
    private var isBlinking = false

    private var supportsAnimatedBackgrounds: Bool {
        if #available(iOS 13.0, *) {
            return true
        }
        return false
    }

    // MARK: - Views

    private let agentPicker = UISegmentedControl()
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let transportStatusLabel = UILabel()
    private let versionLabel = UILabel()

    private let fiveHourTitleLabel = UILabel()
    private let fiveHourValueLabel = UILabel()
    private let fiveHourProgress = UIProgressView(progressViewStyle: .default)

    private let sevenDayTitleLabel = UILabel()
    private let sevenDayValueLabel = UILabel()
    private let sevenDayProgress = UIProgressView(progressViewStyle: .default)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        monitor.delegate = self
        setupViews()
        updateUI()
    }

    // MARK: - Setup

    private func setupViews() {
        view.backgroundColor = .white

        // Agent picker
        agentPicker.translatesAutoresizingMaskIntoConstraints = false
        agentPicker.addTarget(self, action: #selector(agentChanged), for: .valueChanged)
        view.addSubview(agentPicker)

        // Status labels
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = UIFont.systemFont(ofSize: 48, weight: .bold)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 1
        statusLabel.adjustsFontSizeToFitWidth = true

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 2

        transportStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        transportStatusLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        transportStatusLabel.textAlignment = .center
        transportStatusLabel.numberOfLines = 0

        let centerStack = UIStackView(arrangedSubviews: [statusLabel, detailLabel, transportStatusLabel])
        centerStack.axis = .vertical
        centerStack.spacing = 8
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(centerStack)

        // Quota views
        let fiveHourStack = makeQuotaStack(
            title: fiveHourTitleLabel,
            value: fiveHourValueLabel,
            progress: fiveHourProgress,
            titleText: "5H LEFT"
        )
        let sevenDayStack = makeQuotaStack(
            title: sevenDayTitleLabel,
            value: sevenDayValueLabel,
            progress: sevenDayProgress,
            titleText: "7D LEFT"
        )

        let quotaRow = UIStackView(arrangedSubviews: [fiveHourStack, sevenDayStack])
        quotaRow.axis = .horizontal
        quotaRow.distribution = .fillEqually
        quotaRow.spacing = 20
        quotaRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(quotaRow)

        versionLabel.text = appVersion
        if #available(iOS 13.0, *) {
            versionLabel.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        } else {
            versionLabel.font = UIFont(name: "Menlo-Regular", size: 10)
                ?? UIFont.systemFont(ofSize: 10, weight: .regular)
        }
        versionLabel.textColor = UIColor.black.withAlphaComponent(0.25)
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(versionLabel)

        // Layout
        NSLayoutConstraint.activate([
            agentPicker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            agentPicker.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            agentPicker.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.5),

            centerStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            centerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            centerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            quotaRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            quotaRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            quotaRow.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            versionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            versionLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
        ])
    }

    private func makeQuotaStack(
        title: UILabel,
        value: UILabel,
        progress: UIProgressView,
        titleText: String
    ) -> UIStackView {
        title.text = titleText
        title.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        title.textAlignment = .center

        value.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        value.textAlignment = .center
        value.text = "--"

        progress.trackTintColor = UIColor.lightGray.withAlphaComponent(0.3)
        progress.progressTintColor = quotaColor(for: 1.0)

        let stack = UIStackView(arrangedSubviews: [title, value, progress])
        stack.axis = .vertical
        stack.spacing = 4
        return stack
    }

    private func quotaColor(for fraction: Double) -> UIColor {
        let clamped = max(0, min(1, fraction))
        let hue = CGFloat(0.33 * clamped)
        return UIColor(hue: hue, saturation: 0.9, brightness: 0.95, alpha: 1.0)
    }

    private func transportStatusText() -> NSAttributedString {
        let result = NSMutableAttributedString()

        for (index, status) in transportStatuses.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "   "))
            }

            let dot = NSAttributedString(
                string: "●",
                attributes: [
                    .foregroundColor: transportStatusColor(for: status.state),
                    .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                ]
            )
            result.append(dot)

            let text = NSAttributedString(
                string: " \(status.name)\(transportStateText(for: status.state))",
                attributes: [
                    .foregroundColor: UIColor.black.withAlphaComponent(0.72),
                    .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                ]
            )
            result.append(text)
        }

        return result
    }

    private func transportStatusColor(for state: TransportStatus.State) -> UIColor {
        switch state {
        case .connected:
            return UIColor(red: 0.10, green: 0.72, blue: 0.30, alpha: 1.0)
        case .disconnected:
            return UIColor(red: 0.60, green: 0.60, blue: 0.64, alpha: 1.0)
        case .unavailable:
            return UIColor(red: 0.72, green: 0.62, blue: 0.16, alpha: 1.0)
        }
    }

    private func transportStateText(for state: TransportStatus.State) -> String {
        switch state {
        case .connected:
            return "已连接"
        case .disconnected:
            return "未连接"
        case .unavailable:
            return "未配置"
        }
    }

    // MARK: - Working gradient

    private var gradientLayer: CAGradientLayer?

    private func startWorkingAnimation() {
        if gradientLayer != nil {
            return
        }
        stopWorkingAnimation()

        let dark  = UIColor(red: 0.0,  green: 0.30, blue: 0.05, alpha: 1).cgColor
        let mid   = UIColor(red: 0.05, green: 0.60, blue: 0.15, alpha: 1).cgColor
        let light = UIColor(red: 0.45, green: 1.00, blue: 0.45, alpha: 1).cgColor
        let pale  = UIColor(red: 0.80, green: 1.00, blue: 0.80, alpha: 1).cgColor

        let gradient = CAGradientLayer()
        gradient.frame = view.bounds
        gradient.colors = [dark, mid, light, pale]
        gradient.locations = [0.0, 0.35, 0.65, 1.0]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint   = CGPoint(x: 1, y: 0.5)
        view.layer.insertSublayer(gradient, at: 0)
        gradientLayer = gradient

        let colorAnim = CABasicAnimation(keyPath: "colors")
        colorAnim.fromValue = [dark, mid, light, pale]
        colorAnim.toValue   = [pale, light, mid, dark]
        colorAnim.duration = 3.0
        colorAnim.autoreverses = true
        colorAnim.repeatCount = .infinity
        colorAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradient.add(colorAnim, forKey: "colors")

        let locAnim = CABasicAnimation(keyPath: "locations")
        locAnim.fromValue = [0.0, 0.35, 0.65, 1.0]
        locAnim.toValue   = [0.0, 0.25, 0.75, 1.0]
        locAnim.duration = 2.0
        locAnim.autoreverses = true
        locAnim.repeatCount = .infinity
        locAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradient.add(locAnim, forKey: "locations")
    }

    private func stopWorkingAnimation() {
        gradientLayer?.removeFromSuperlayer()
        gradientLayer = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer?.frame = view.bounds
    }

    // MARK: - Blink

    private func startBlinkAnimation() {
        if isBlinking {
            return
        }
        isBlinking = true
        view.layer.removeAllAnimations()
        view.backgroundColor = .red
        UIView.animate(withDuration: 0.5, delay: 0,
                       options: [.repeat, .autoreverse, .allowUserInteraction],
                       animations: { self.view.backgroundColor = UIColor(red: 0.55, green: 0.0, blue: 0.0, alpha: 1) },
                       completion: nil)
    }

    private func stopBlinkAnimation() {
        if !isBlinking {
            return
        }
        isBlinking = false
        view.layer.removeAllAnimations()
    }

    // MARK: - Updates

    private func updateUI() {
        let status = statuses[selectedAgentID] ?? .idle
        let agentName = StatusAggregator.displayName(for: selectedAgentID)

        // Only switch background animation when status actually changes.
        if renderedStatus != status {
            if !supportsAnimatedBackgrounds {
                // iOS12 devices are more prone to frame drops with repeating
                // full-screen animations; use static backgrounds for stability.
                stopBlinkAnimation()
                stopWorkingAnimation()
                view.backgroundColor = backgroundColor(for: status)
            } else {
                if status == .awaitingApproval {
                    stopWorkingAnimation()
                    startBlinkAnimation()
                } else if status == .working {
                    stopBlinkAnimation()
                    startWorkingAnimation()
                } else {
                    stopBlinkAnimation()
                    stopWorkingAnimation()
                    UIView.animate(withDuration: 0.3) {
                        self.view.backgroundColor = self.backgroundColor(for: status)
                    }
                }
            }
            renderedStatus = status
        }

        // Labels
        statusLabel.text = statusTitle(for: status, agentName: agentName)
        detailLabel.text = statusDetail(for: status, agentName: agentName)
        transportStatusLabel.attributedText = transportStatusText()

        // Agent picker
        if agentPicker.numberOfSegments != availableAgents.count {
            agentPicker.removeAllSegments()
            for (i, id) in availableAgents.enumerated() {
                agentPicker.insertSegment(withTitle: StatusAggregator.displayName(for: id), at: i, animated: false)
            }
        }
        if let idx = availableAgents.firstIndex(of: selectedAgentID) {
            agentPicker.selectedSegmentIndex = idx
        }
        agentPicker.isHidden = availableAgents.count <= 1

        // Quota
        fiveHourProgress.setProgress(Float(quotas.fiveHourFraction), animated: true)
        sevenDayProgress.setProgress(Float(quotas.sevenDayFraction), animated: true)
        fiveHourProgress.progressTintColor = quotaColor(for: quotas.fiveHourFraction)
        sevenDayProgress.progressTintColor = quotaColor(for: quotas.sevenDayFraction)

        if let hours = quotas.fiveHourRemainingHours {
            fiveHourValueLabel.text = String(format: "%.1fh (%.0f%%)", hours, quotas.fiveHourFraction * 100)
        } else {
            fiveHourValueLabel.text = String(format: "%.0f%%", quotas.fiveHourFraction * 100)
        }
        if let days = quotas.sevenDayRemainingDays {
            sevenDayValueLabel.text = String(format: "%.1fd (%.0f%%)", days, quotas.sevenDayFraction * 100)
        } else {
            sevenDayValueLabel.text = String(format: "%.0f%%", quotas.sevenDayFraction * 100)
        }
    }

    private func backgroundColor(for status: AgentStatus) -> UIColor {
        switch status {
        case .working: return UIColor(red: 0.94, green: 0.98, blue: 0.94, alpha: 1)
        case .idle: return .white
        case .awaitingApproval: return UIColor(red: 0.96, green: 0.82, blue: 0.82, alpha: 1)
        case .unknown: return UIColor.lightGray.withAlphaComponent(0.25)
        }
    }

    private func statusTitle(for status: AgentStatus, agentName: String) -> String {
        switch status {
        case .working: return "\(agentName.uppercased()) THINKING"
        case .idle: return "\(agentName.uppercased()) IDLE"
        case .awaitingApproval: return "\(agentName.uppercased()) APPROVE"
        case .unknown: return "UNKNOWN"
        }
    }

    private func statusDetail(for status: AgentStatus, agentName: String) -> String {
        switch status {
        case .working: return "\(agentName) 正在思考或执行任务"
        case .idle: return "\(agentName) 当前空闲"
        case .awaitingApproval: return "\(agentName) 正在等待你的介入"
        case .unknown: return "尚未收到状态"
        }
    }

    @objc private func agentChanged() {
        let idx = agentPicker.selectedSegmentIndex
        guard idx >= 0, idx < availableAgents.count else { return }
        selectedAgentID = availableAgents[idx]
        updateUI()
    }
}

// MARK: - StatusMonitorDelegate

extension StatusViewController: StatusMonitorDelegate {
    func monitorDidConnect() {
        transportStatuses = monitor.transportStatuses
        updateUI()
    }

    func monitorDidDisconnect() {
        statuses = [:]
        availableAgents = []
        claudeQuota = .fallback
        codexQuota = .fallback
        transportStatuses = monitor.transportStatuses
        updateUI()
    }

    func monitorDidReceive(_ snapshot: StatusSnapshot) {
        statuses = snapshot.agents

        let order = ["codex", "claude"]
        availableAgents = snapshot.agents.keys.sorted {
            let i0 = order.firstIndex(of: $0) ?? Int.max
            let i1 = order.firstIndex(of: $1) ?? Int.max
            return i0 < i1
        }

        claudeQuota = snapshot.quotas?["claude"]?.asQuotaSnapshot() ?? .fallback
        codexQuota = snapshot.quotas?["codex"]?.asQuotaSnapshot() ?? .fallback

        transportStatuses = monitor.transportStatuses

        if !availableAgents.contains(selectedAgentID),
           let first = availableAgents.first {
            selectedAgentID = first
        }

        updateUI()
    }
}
