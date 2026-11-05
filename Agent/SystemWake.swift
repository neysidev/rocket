import Foundation
import IOKit.pwr_mgt

/// Wake-from-sleep events from the power manager. The agent has no AppKit run loop, so this uses IOKit's
/// system power notifications delivered on a dispatch queue instead of NSWorkspace.
enum SystemWake {
    /// Yields once each time the Mac finishes waking. ponytail: one registration for the agent's lifetime;
    /// it is never torn down because the agent iterates this until it exits.
    static func events() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let box = Unmanaged.passRetained(Box(continuation: continuation))
        var port: IONotificationPortRef?
        var notifier: io_object_t = 0
        box.takeUnretainedValue().root = IORegisterForSystemPower(box.toOpaque(), &port, { refcon, _, messageType, argument in
            guard let refcon else { return }
            let box = Unmanaged<Box>.fromOpaque(refcon).takeUnretainedValue()
            switch messageType {
            case Message.canSystemSleep, Message.systemWillSleep:
                // Sleep must be acknowledged or the system waits up to 30 s for us.
                IOAllowPowerChange(box.root, Int(bitPattern: argument))
            case Message.systemHasPoweredOn:
                box.continuation.yield()
            default:
                break
            }
        }, &notifier)
        if let port {
            IONotificationPortSetDispatchQueue(port, DispatchQueue(label: "io.github.neysidev.rocket.power"))
        } else {
            continuation.finish()
        }
        return stream
    }

    /// `kIOMessage…` values from IOMessage.h; they are function-like C macros, which Swift does not import.
    private enum Message {
        static let canSystemSleep: UInt32 = 0xE000_0270
        static let systemWillSleep: UInt32 = 0xE000_0280
        static let systemHasPoweredOn: UInt32 = 0xE000_0300
    }

    private final class Box: @unchecked Sendable {
        let continuation: AsyncStream<Void>.Continuation
        var root: io_connect_t = 0
        init(continuation: AsyncStream<Void>.Continuation) { self.continuation = continuation }
    }
}
