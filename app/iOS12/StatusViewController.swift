import UIKit

final class StatusViewController: UIViewController {
    private let monitor = StatusAggregator()

    private var statuses: [String: AgentStatus] = [:]
    private var availableAgents: [String] = []
    private var selectedAgentID = "codex"
    private var quotas: QuotaSnapshot = .fallback

    // MARK: - Views

    private let agentPicker = UISegmentedControl()
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let connectionLabel = UILabel()

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

        connectionLabel.translatesAutoresizingMaskIntoConstraints = false
        connectionLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        connectionLabel.textAlignment = .center

        let centerStack = UIStackView(arrangedSubviews: [statusLabel, detailLabel, connectionLabel])
        centerStack.axis = .vertical
        centerStack.spacing = 10
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
        progress.progressTintColor = .systemGreen

        let stack = UIStackView(arrangedSubviews: [title, value, progress])
        stack.axis = .vertical
        stack.spacing = 4
        return stack
    }

    // MARK: - Working gradient

    private var gradientLayer: CAGradientLayer?

    private func startWorkingAnimation() {
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
        view.layer.removeAllAnimations()
        view.backgroundColor = .red
        UIView.animate(withDuration: 0.5, delay: 0,
                       options: [.repeat, .autoreverse, .allowUserInteraction],
                       animations: { self.view.backgroundColor = UIColor(red: 0.55, green: 0.0, blue: 0.0, alpha: 1) },
                       completion: nil)
    }

    private func stopBlinkAnimation() {
        view.layer.removeAllAnimations()
    }

    // MARK: - Updates

    private func updateUI() {
        let status = statuses[selectedAgentID] ?? .unknown
        let agentName = StatusAggregator.displayName(for: selectedAgentID)

        // Background color
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

        // Labels
        statusLabel.text = statusTitle(for: status, agentName: agentName)
        detailLabel.text = statusDetail(for: status, agentName: agentName)
        connectionLabel.text = monitor.isConnected ? "BLE: Connected" : "BLE: Disconnected"

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

        if let hours = quotas.fiveHourRemainingHours {
            fiveHourValueLabel.text = String(format: "%.1fh (%.0f%%)", hours, quotas.fiveHourFraction * 100)
        } else {
            fiveHourValueLabel.text = "--"
        }
        if let days = quotas.sevenDayRemainingDays {
            sevenDayValueLabel.text = String(format: "%.1fd (%.0f%%)", days, quotas.sevenDayFraction * 100)
        } else {
            sevenDayValueLabel.text = "--"
        }
    }

    private func backgroundColor(for status: AgentStatus) -> UIColor {
        switch status {
        case .working: return UIColor(red: 0.9, green: 1.0, blue: 0.9, alpha: 1)
        case .idle: return .white
        case .awaitingApproval: return .red
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
        updateUI()
    }

    func monitorDidDisconnect() {
        statuses = [:]
        availableAgents = []
        quotas = .fallback
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

        quotas = snapshot.quotas?.asQuotaSnapshot()
            ?? snapshot.codexQuota?.asQuotaSnapshot()
            ?? .fallback

        if !availableAgents.contains(selectedAgentID),
           let first = availableAgents.first {
            selectedAgentID = first
        }

        updateUI()
    }
}
