import Foundation

protocol NetworkMonitoring: AnyObject {
    func start()
    func stop()
}

#if canImport(Network)
import Network

final class NetworkMonitor: NetworkMonitoring, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "LoeBalance.NetworkMonitor")
    private let statusChanged: @Sendable (Bool) -> Void
    private var lastAvailability: Bool?

    init(statusChanged: @escaping @Sendable (Bool) -> Void) {
        self.statusChanged = statusChanged
    }

    func start() {
        monitor.pathUpdateHandler = { [statusChanged] path in
            let available = path.status == .satisfied
            if self.lastAvailability != available {
                self.lastAvailability = available
                statusChanged(available)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() { monitor.cancel() }
}
#endif
