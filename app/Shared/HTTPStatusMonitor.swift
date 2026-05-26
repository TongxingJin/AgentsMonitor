import Foundation

final class HTTPStatusMonitor: NSObject {
    weak var delegate: StatusMonitorDelegate?
    private(set) var isConnected = false

    private var resolvedURL: URL?
    private var pollTimer: Timer?
    private var consecutiveFailures = 0
    private static let failureThreshold = 3

    private let browser = NetServiceBrowser()
    private var activeService: NetService?

    override init() {
        super.init()
        browser.delegate = self
        browser.searchForServices(ofType: "_agentbeacon._tcp.", inDomain: "local.")
    }

    private func startPolling(url: URL) {
        resolvedURL = url
        consecutiveFailures = 0
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        resolvedURL = nil
        if isConnected {
            isConnected = false
            delegate?.monitorDidDisconnect()
        }
    }

    private func poll() {
        guard let url = resolvedURL else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard let data = data,
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let snapshot = try? JSONDecoder().decode(StatusSnapshot.self, from: data) else {
                    self.consecutiveFailures += 1
                    if self.isConnected && self.consecutiveFailures >= HTTPStatusMonitor.failureThreshold {
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

extension HTTPStatusMonitor: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        activeService = service
        service.delegate = self
        service.resolve(withTimeout: 10.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        guard service == activeService else { return }
        activeService = nil
        stopPolling()
    }
}

extension HTTPStatusMonitor: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName else { return }
        let url = URL(string: "http://\(host):\(sender.port)/status")!
        startPolling(url: url)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        activeService = nil
    }
}
