import SwiftUI
import UIKit

private struct RingSpec: Identifiable {
    let id: Int
    let color: Color
    let diameterRatio: CGFloat
    let lineWidth: CGFloat
    let amplitudeX: CGFloat
    let amplitudeY: CGFloat
    let speed: Double
    let phaseX: Double
    let phaseY: Double
    let centerX: CGFloat
    let centerY: CGFloat
    let opacity: Double
}

private let ringSpecs: [RingSpec] = [
    RingSpec(id: 0, color: .blue, diameterRatio: 0.34, lineWidth: 16, amplitudeX: 0.18, amplitudeY: 0.11, speed: 0.85, phaseX: 0.2, phaseY: 2.1, centerX: 0.28, centerY: 0.34, opacity: 0.86),
    RingSpec(id: 1, color: .orange, diameterRatio: 0.26, lineWidth: 12, amplitudeX: 0.15, amplitudeY: 0.18, speed: 1.1, phaseX: 2.4, phaseY: 1.0, centerX: 0.72, centerY: 0.30, opacity: 0.82),
    RingSpec(id: 2, color: .pink, diameterRatio: 0.22, lineWidth: 10, amplitudeX: 0.16, amplitudeY: 0.14, speed: 0.94, phaseX: 1.7, phaseY: 4.3, centerX: 0.63, centerY: 0.67, opacity: 0.78),
    RingSpec(id: 3, color: .mint, diameterRatio: 0.30, lineWidth: 14, amplitudeX: 0.19, amplitudeY: 0.12, speed: 0.72, phaseX: 3.1, phaseY: 5.0, centerX: 0.30, centerY: 0.70, opacity: 0.8),
    RingSpec(id: 4, color: .yellow, diameterRatio: 0.18, lineWidth: 9, amplitudeX: 0.12, amplitudeY: 0.17, speed: 1.22, phaseX: 5.2, phaseY: 2.9, centerX: 0.48, centerY: 0.43, opacity: 0.76),
    RingSpec(id: 5, color: .cyan, diameterRatio: 0.14, lineWidth: 8, amplitudeX: 0.22, amplitudeY: 0.10, speed: 1.35, phaseX: 4.0, phaseY: 0.8, centerX: 0.52, centerY: 0.56, opacity: 0.7)
]

private struct WorkingRingsBackground: View {
    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate

                ZStack {
                    Color.white

                    ForEach(ringSpecs) { ring in
                        Circle()
                            .stroke(ring.color.opacity(ring.opacity), lineWidth: ring.lineWidth)
                            .frame(
                                width: geometry.size.width * ring.diameterRatio,
                                height: geometry.size.width * ring.diameterRatio
                            )
                            .position(
                                x: xPosition(for: ring, time: time, size: geometry.size),
                                y: yPosition(for: ring, time: time, size: geometry.size)
                            )
                            .blur(radius: 0.2)
                    }
                }
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
        }
    }

    private func xPosition(for ring: RingSpec, time: TimeInterval, size: CGSize) -> CGFloat {
        let drift = sin(time * ring.speed + ring.phaseX) * ring.amplitudeX
        return size.width * (ring.centerX + drift)
    }

    private func yPosition(for ring: RingSpec, time: TimeInterval, size: CGSize) -> CGFloat {
        let drift = cos(time * ring.speed * 0.93 + ring.phaseY) * ring.amplitudeY
        return size.height * (ring.centerY + drift)
    }
}

private struct ApprovalPulseBackground: View {
    @State private var dimmed = false

    var body: some View {
        Rectangle()
            .fill(dimmed ? Color(red: 0.55, green: 0.0, blue: 0.0) : Color.red)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

private struct QuotaCylinderView: View {
    let title: String
    let valueText: String
    let percentText: String
    let fraction: Double

    private var clampedFraction: Double {
        min(max(fraction, 0.0), 1.0)
    }

    private var fillGradient: LinearGradient {
        let topColor = gradientAnchorColor
        let bottomColor = bottomAnchorColor
        return LinearGradient(
            colors: [
                topColor.opacity(0.95),
                topColor,
                bottomColor
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private var gradientAnchorColor: Color {
        switch clampedFraction {
        case ..<0.2:
            return Color(red: 0.82, green: 0.16, blue: 0.18)
        case ..<0.4:
            return Color(red: 0.92, green: 0.36, blue: 0.18)
        case ..<0.65:
            return Color(red: 0.95, green: 0.70, blue: 0.18)
        case ..<0.85:
            return Color(red: 0.52, green: 0.78, blue: 0.22)
        default:
            return Color(red: 0.16, green: 0.70, blue: 0.34)
        }
    }

    private var bottomAnchorColor: Color {
        switch clampedFraction {
        case ..<0.35:
            return Color(red: 0.99, green: 0.83, blue: 0.40)
        case ..<0.7:
            return Color(red: 0.72, green: 0.84, blue: 0.30)
        default:
            return Color(red: 0.30, green: 0.78, blue: 0.42)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let topInset = min(92.0, height * 0.24)
            let baseInset = 12.0
            let cylinderHeight = max(0, height - topInset - baseInset)
            let fillHeight = max(18, cylinderHeight * clampedFraction)

            ZStack(alignment: .top) {
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.07))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.7), lineWidth: 1)
                    )
                    .padding(.top, topInset)
                    .padding(.bottom, baseInset)

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.black.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(valueText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.black.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(percentText)
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: width * 0.94)
                .padding(.top, 8)

                VStack {
                    Spacer(minLength: topInset + cylinderHeight - fillHeight)

                    ZStack(alignment: .top) {
                        Capsule(style: .continuous)
                            .fill(fillGradient)

                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.22))
                            .frame(width: width * 0.18)
                            .padding(.leading, width * 0.18)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Ellipse()
                            .fill(Color.white.opacity(0.32))
                            .frame(width: width * 0.78, height: 14)
                            .padding(.top, 6)
                    }
                    .frame(width: width, height: fillHeight)

                    Spacer(minLength: baseInset)
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var monitor = BLEStatusViewModel()
    @State private var showingTailscaleSettings = false

    var body: some View {
        ZStack {
            backgroundLayer
                .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    if !monitor.availableAgents.isEmpty {
                        AgentTabPicker(
                            agents: monitor.availableAgents,
                            selected: Binding(
                                get: { monitor.selectedAgentID },
                                set: { monitor.selectAgent($0) }
                            )
                        )
                    }

                    Button {
                        showingTailscaleSettings = true
                    } label: {
                        Image(systemName: "network")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black.opacity(0.78))
                            .frame(width: 38, height: 38)
                            .background(Color.black.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showingTailscaleSettings) {
                        TailscaleSettingsView(initialHosts: monitor.tailscaleHosts) { hosts in
                            monitor.applyTailscaleHosts(hosts)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)

                GeometryReader { geometry in
                    HStack(spacing: 6) {
                        quotaView(
                            title: "5H LEFT",
                            valueText: fiveHourText,
                            percentText: fiveHourPercentText,
                            fraction: fiveHourFraction
                        )
                        .frame(width: cylinderColumnWidth(in: geometry.size.width))

                        centerPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        quotaView(
                            title: "7D LEFT",
                            valueText: sevenDayText,
                            percentText: sevenDayPercentText,
                            fraction: sevenDayFraction
                        )
                        .frame(width: cylinderColumnWidth(in: geometry.size.width))
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            updateIdleTimer()
        }
        .onChange(of: monitor.isConnected) { _, _ in
            updateIdleTimer()
        }
    }

    private func quotaView(
        title: String,
        valueText: String,
        percentText: String,
        fraction: Double
    ) -> some View {
        QuotaCylinderView(
            title: title,
            valueText: valueText,
            percentText: percentText,
            fraction: fraction
        )
    }

    private var currentStatus: AgentStatus {
        monitor.currentStatus
    }

    private var fiveHourFraction: Double {
        monitor.quotas.fiveHourFraction
    }

    private var sevenDayFraction: Double {
        monitor.quotas.sevenDayFraction
    }

    private var fiveHourText: String {
        if let hours = monitor.quotas.fiveHourRemainingHours {
            return String(format: "%.1fh", hours)
        }
        return "--"
    }

    private var sevenDayText: String {
        if let days = monitor.quotas.sevenDayRemainingDays {
            return String(format: "%.1fd", days)
        }
        return "--"
    }

    private var fiveHourPercentText: String {
        String(format: "%.0f%%", fiveHourFraction * 100)
    }

    private var sevenDayPercentText: String {
        String(format: "%.0f%%", sevenDayFraction * 100)
    }

    private func cylinderColumnWidth(in totalWidth: CGFloat) -> CGFloat {
        min(80, max(62, totalWidth * 0.10))
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        switch currentStatus {
        case .working:
            WorkingRingsBackground()
        case .idle:
            Color.white
        case .awaitingApproval:
            ApprovalPulseBackground()
        case .unknown:
            Color.gray.opacity(0.25)
        }
    }

    private var overlayCardColor: Color {
        switch currentStatus {
        case .working:
            return Color.white.opacity(0.72)
        case .idle:
            return Color.black.opacity(0.03)
        case .awaitingApproval:
            return Color.white.opacity(0.86)
        case .unknown:
            return Color.white.opacity(0.78)
        }
    }

    private var centerPanel: some View {
        VStack(spacing: 18) {
            Spacer()

            VStack(spacing: 12) {
                Text(titleText)
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .foregroundColor(.black)

                Text(detailText)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundColor(.black.opacity(0.72))

                Text(monitor.isConnected ? "Connected" : "Scanning…")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.08))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 26)
            .background(overlayCardColor)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            Spacer()
        }
        .multilineTextAlignment(.center)
    }

    private var titleText: String {
        switch currentStatus {
        case .working:
            return "\(monitor.selectedAgentName.uppercased()) THINKING"
        case .idle:
            return "\(monitor.selectedAgentName.uppercased()) IDLE"
        case .awaitingApproval:
            return "\(monitor.selectedAgentName.uppercased()) APPROVE"
        case .unknown:
            return "UNKNOWN"
        }
    }

    private var detailText: String {
        switch currentStatus {
        case .working:
            return "\(monitor.selectedAgentName) 正在思考或执行任务"
        case .idle:
            return "\(monitor.selectedAgentName) 当前空闲"
        case .awaitingApproval:
            return "\(monitor.selectedAgentName) 正在等待你的介入"
        case .unknown:
            return "尚未收到状态"
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = monitor.isConnected
    }
}

private struct AgentTabPicker: View {
    let agents: [String]
    @Binding var selected: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(agents, id: \.self) { agentID in
                let isSelected = agentID == selected
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selected = agentID
                    }
                } label: {
                    Text(BLEStatusMonitor.displayName(for: agentID))
                        .font(.system(size: 15, weight: isSelected ? .bold : .regular, design: .rounded))
                        .foregroundColor(isSelected ? .white : .black.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            Group {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.black.opacity(0.82))
                                        .padding(.horizontal, 4)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.black.opacity(0.09))
        .clipShape(Capsule())
    }
}
