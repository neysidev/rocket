import Foundation
import Network

/// Whether the Mac currently has a usable network path. Network loss and wake from sleep both show up here.
public enum NetworkReachability {
    /// Emits the current state immediately, then every change, until the consumer stops iterating.
    public static func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { continuation.yield($0.status == .satisfied) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "io.github.neysidev.rocket.reachability"))
        }
    }
}
