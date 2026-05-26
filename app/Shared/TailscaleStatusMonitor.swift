import Foundation

final class TailscaleStatusMonitor {
    weak var delegate: StatusMonitorDelegate?
    private(set) var isConnected = false
    let host: String

    private let url: URL?
    private var pollTimer: Timer?
    private var consecutiveFailures = 0
    private static let failureThreshold = 3

    init(host: String) {
        self.host = host
        url = URL(string: "http://\(host):8765/status")
    }

    func start() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if isConnected {
            isConnected = false
            delegate?.monitorDidDisconnect()
        }
    }

    private func poll() {
        guard let url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let data,
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let snapshot = try? JSONDecoder().decode(StatusSnapshot.self, from: data) else {
                    self.consecutiveFailures += 1
                    if self.isConnected && self.consecutiveFailures >= Self.failureThreshold {
                        self.isConnected = false
                        self.delegate?.monitorDidDisconnect()
                    }
                    return
                }
                self.consecutiveFailures = 0
                if !self.isConnected {
                    self.isConnected = true
                    self.delegate?.monitorDidConnect()
                }
                self.delegate?.monitorDidReceive(snapshot)
            }
        }.resume()
    }
}
