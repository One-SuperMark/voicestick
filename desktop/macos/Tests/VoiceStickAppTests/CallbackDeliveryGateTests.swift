import Foundation
import XCTest
@testable import VoiceStickApp

final class CallbackDeliveryGateTests: XCTestCase {
    func testCancelInvalidatesAlreadyQueuedDeliveryImmediately() {
        let gate = CallbackDeliveryGate()
        let ticket = gate.begin()
        var delivered = false
        let delivery = gate.snapshotDelivery(for: ticket) { delivered = true }

        gate.invalidate()
        delivery()

        XCTAssertFalse(delivered)
        XCTAssertNil(gate.currentTicket)
        XCTAssertFalse(gate.isCurrent(ticket))
    }

    func testNewStartInvalidatesOldDeliveryAndAcceptsNewDelivery() {
        let gate = CallbackDeliveryGate()
        let oldTicket = gate.begin()
        var oldCount = 0
        let oldDelivery = gate.snapshotDelivery(for: oldTicket) { oldCount += 1 }
        let newTicket = gate.begin()
        var newCount = 0
        let newDelivery = gate.snapshotDelivery(for: newTicket) { newCount += 1 }

        oldDelivery()
        newDelivery()

        XCTAssertNotEqual(oldTicket, newTicket)
        XCTAssertEqual(oldCount, 0)
        XCTAssertEqual(newCount, 1)
        XCTAssertEqual(gate.currentTicket, newTicket)
    }

    func testSuccessfulFinalStillDeliversAfterNetworkSessionIDIsCleared() {
        let gate = CallbackDeliveryGate()
        let ticket = gate.begin()
        var networkSessionID: String? = "synthetic-session"
        var finalCount = 0
        let finalDelivery = gate.snapshotDelivery(for: ticket) { finalCount += 1 }

        networkSessionID = nil
        finalDelivery()

        XCTAssertNil(networkSessionID)
        XCTAssertEqual(finalCount, 1)
        XCTAssertTrue(gate.isCurrent(ticket))
    }

    func testCallbackSnapshotDoesNotReadAReplacementHandler() {
        let gate = CallbackDeliveryGate()
        let ticket = gate.begin()
        var oldCount = 0
        var replacementCount = 0
        var callback: () -> Void = { oldCount += 1 }
        let delivery = gate.snapshotDelivery(for: ticket, perform: callback)

        callback = { replacementCount += 1 }
        delivery()

        XCTAssertEqual(oldCount, 1)
        XCTAssertEqual(replacementCount, 0)
        callback()
        XCTAssertEqual(replacementCount, 1)
    }

    func testOldSerialCleanupDoesNotInvalidateNewStart() {
        let gate = CallbackDeliveryGate()
        let oldTicket = gate.begin()
        let currentTicket = gate.begin()

        gate.invalidate(oldTicket)

        XCTAssertEqual(gate.currentTicket, currentTicket)
        XCTAssertTrue(gate.isCurrent(currentTicket))
    }

    func testServerCancellationInvalidatesItsCurrentTicket() {
        let gate = CallbackDeliveryGate()
        let ticket = gate.begin()
        var delivered = false
        let delivery = gate.snapshotDelivery(for: ticket) { delivered = true }

        gate.invalidate(ticket)
        delivery()

        XCTAssertFalse(delivered)
        XCTAssertNil(gate.currentTicket)
    }

    func testErrorAndUpgradeRemainOneNotificationAcrossReentrantCancel() {
        let gate = CallbackDeliveryGate()
        let ticket = gate.begin()
        var events: [String] = []
        let notification = gate.snapshotDelivery(for: ticket) {
            events.append("error")
            gate.invalidate()
            events.append("upgrade")
        }

        notification()
        notification()

        XCTAssertEqual(events, ["error", "upgrade"])
        XCTAssertNil(gate.currentTicket)
    }

    func testReentrantStartDoesNotDeadlockAndInvalidatesFollowingOldDelivery() {
        let gate = CallbackDeliveryGate()
        let ticket = gate.begin()
        var nextTicket: CallbackDeliveryGate.Ticket?
        var oldCount = 0
        let firstDelivery = gate.snapshotDelivery(for: ticket) { nextTicket = gate.begin() }
        let oldDelivery = gate.snapshotDelivery(for: ticket) { oldCount += 1 }

        firstDelivery()
        oldDelivery()

        XCTAssertEqual(oldCount, 0)
        XCTAssertNotNil(nextTicket)
        XCTAssertEqual(gate.currentTicket, nextTicket)
    }

    func testConcurrentStartsKeepOnlyOneUniqueCurrentTicket() {
        let gate = CallbackDeliveryGate()
        let ticketsLock = NSLock()
        var tickets: [CallbackDeliveryGate.Ticket] = []
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            let ticket = gate.begin()
            ticketsLock.lock()
            tickets.append(ticket)
            ticketsLock.unlock()
        }

        XCTAssertEqual(Set(tickets).count, 200)
        XCTAssertEqual(tickets.filter { gate.isCurrent($0) }.count, 1)
        gate.invalidate()
        XCTAssertTrue(tickets.allSatisfy { !gate.isCurrent($0) })
    }

    func testTicketFromAnotherClientCannotDeliver() {
        let firstGate = CallbackDeliveryGate()
        let otherGate = CallbackDeliveryGate()
        let foreignTicket = firstGate.begin()
        _ = otherGate.begin()
        var delivered = false
        let delivery = otherGate.snapshotDelivery(for: foreignTicket) { delivered = true }

        delivery()

        XCTAssertFalse(delivered)
    }
}
