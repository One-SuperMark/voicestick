import Foundation

/// Separates callback lifetime from the WebSocket session ID, which is cleared
/// before a successful final result is delivered on the main queue.
final class CallbackDeliveryGate {
    struct Ticket: Hashable {
        fileprivate let identifier = UUID()
    }

    // Delivery is linearized with start/cancel. A callback may synchronously
    // call either operation, so this lock must allow same-thread reentrancy.
    private let lock = NSRecursiveLock()
    private var activeTicket: Ticket?

    var currentTicket: Ticket? {
        lock.lock()
        defer { lock.unlock() }
        return activeTicket
    }

    @discardableResult
    func begin() -> Ticket {
        lock.lock()
        defer { lock.unlock() }
        let ticket = Ticket()
        activeTicket = ticket
        return ticket
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        activeTicket = nil
    }

    /// Serial cleanup for an older session must not invalidate a newer start.
    func invalidate(_ ticket: Ticket) {
        lock.lock()
        defer { lock.unlock() }
        if activeTicket == ticket {
            activeTicket = nil
        }
    }

    func isCurrent(_ ticket: Ticket) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeTicket == ticket
    }

    /// Captures the supplied callback now, not when a dispatch queue runs it.
    /// A related callback group (for example error + upgrade URL) can be passed
    /// as one action so a reentrant cancel does not split that one notification.
    func snapshotDelivery(for ticket: Ticket, perform action: @escaping () -> Void) -> () -> Void {
        { [weak self] in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard self.activeTicket == ticket else { return }
            action()
        }
    }
}
