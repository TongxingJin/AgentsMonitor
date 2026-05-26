import Foundation
import Network

final class USBStatusMonitor {
    weak var delegate: StatusMonitorDelegate?
    private(set) var isConnected = false

    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "usb-status-monitor")
    private var buffer = Data()

    static let port: NWEndpoint.Port = 9000

    init() {
        startListening()
    }

    private func startListening() {
        guard let listener = try? NWListener(using: .tcp, on: USBStatusMonitor.port) else { return }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.start(queue: queue)
    }

    private func accept(_ conn: NWConnection) {
        connection?.cancel()
        connection = conn
        buffer = Data()
        conn.start(queue: queue)
        DispatchQueue.main.async {
            self.isConnected = true
            self.delegate?.monitorDidConnect()
        }
        receive(from: conn)
    }

    private func receive(from conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.flush()
            }
            if isComplete || error != nil {
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.delegate?.monitorDidDisconnect()
                }
                conn.cancel()
            } else {
                self.receive(from: conn)
            }
        }
    }

    private func flush() {
        while let idx = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<idx]
            buffer = Data(buffer[buffer.index(after: idx)...])
            if let snapshot = try? JSONDecoder().decode(StatusSnapshot.self, from: line) {
                DispatchQueue.main.async { self.delegate?.monitorDidReceive(snapshot) }
            }
        }
    }
}
