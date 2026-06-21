import Foundation
import Network
import os

@Observable
@MainActor
final class NetworkMonitor {
    private nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NetworkMonitor")

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.aetherium.Pr0gramm.NetworkMonitor")
    private var hasStarted = false

    var isConnected = true

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isConnected != isConnected {
                    Self.logger.info("Network connectivity changed. Connected: \(isConnected)")
                }
                self.isConnected = isConnected
            }
        }
        monitor.start(queue: monitorQueue)
    }

    nonisolated deinit {
        monitor.cancel()
    }
}
