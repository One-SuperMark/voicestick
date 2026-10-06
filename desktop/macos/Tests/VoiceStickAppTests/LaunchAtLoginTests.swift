import AppKit
import ServiceManagement
import XCTest
@testable import VoiceStickApp

final class LaunchAtLoginTests: XCTestCase {
    private final class Service: LaunchAtLoginService {
        var state: LaunchAtLoginState = .disabled
        var registeredState: LaunchAtLoginState = .enabled
        var registrations = 0
        var removals = 0
        var fail = false
        func register() throws {
            registrations += 1
            if fail { throw NSError(domain: "LaunchAtLoginTests", code: 1) }
            state = registeredState
        }
        func unregister() throws {
            removals += 1
            if fail { throw NSError(domain: "LaunchAtLoginTests", code: 2) }
            state = .disabled
        }
        func openSystemSettings() { XCTFail("Tests must not open System Settings") }
    }

    private func makeMenu(_ service: Service) -> (LaunchAtLoginController, NSMenu) {
        let controller = LaunchAtLoginController(service: service)
        let menu = NSMenu()
        controller.addMenuItems(to: menu)
        return (controller, menu)
    }

    func testNativeStatusMappingAllowsFirstRegistration() throws {
        guard #available(macOS 13.0, *) else { throw XCTSkip("Requires SMAppService") }
        XCTAssertEqual(LaunchAtLoginState.fromSystemStatus(.notFound), .disabled)
        XCTAssertEqual(LaunchAtLoginState.fromSystemStatus(.notRegistered), .disabled)
        XCTAssertEqual(LaunchAtLoginState.fromSystemStatus(.enabled), .enabled)
        XCTAssertEqual(LaunchAtLoginState.fromSystemStatus(.requiresApproval), .requiresApproval)
    }

    func testNotFoundItemIsClickableAndRegistersInsteadOfRemainingGrey() throws {
        guard #available(macOS 13.0, *) else { throw XCTSkip("Requires SMAppService") }
        let service = Service()
        service.state = .fromSystemStatus(.notFound)
        let (controller, menu) = makeMenu(service)
        XCTAssertEqual(menu.items[0].state, .off)
        XCTAssertTrue(menu.items[0].isEnabled)
        XCTAssertTrue(controller.validateMenuItem(menu.items[0]))
        try controller.toggleRegistration()
        XCTAssertEqual(service.registrations, 1)
        XCTAssertEqual(service.removals, 0)
        XCTAssertEqual(menu.items[0].state, .on)
    }

    func testLoginMenuTitlesHaveNoEllipsis() {
        let service = Service()
        service.state = .requiresApproval
        let (_, menu) = makeMenu(service)
        for item in menu.items {
            XCTAssertFalse(item.title.contains("…"))
            XCTAssertFalse(item.title.contains("..."))
        }
    }

    func testCreatingAndOpeningMenuNeverRegisters() {
        let service = Service()
        let (controller, menu) = makeMenu(service)
        controller.menuWillOpen(menu)
        XCTAssertEqual(service.registrations, 0)
        XCTAssertEqual(service.removals, 0)
        XCTAssertEqual(menu.items[0].title, "开机启动")
        XCTAssertEqual(menu.items[0].state, .off)
        XCTAssertTrue(menu.items[1].isHidden)
        XCTAssertTrue(menu.items[0].target === controller)
        XCTAssertTrue(controller.responds(to: menu.items[0].action!))
    }

    func testEnableAndDisableReadBackSystemState() throws {
        let service = Service()
        let (controller, menu) = makeMenu(service)
        try controller.toggleRegistration()
        XCTAssertEqual(service.registrations, 1)
        XCTAssertEqual(menu.items[0].state, .on)
        try controller.toggleRegistration()
        XCTAssertEqual(service.removals, 1)
        XCTAssertEqual(menu.items[0].state, .off)
    }

    func testApprovalIsMixedNotEnabledAndCanBeCancelled() throws {
        let service = Service()
        service.registeredState = .requiresApproval
        let (controller, menu) = makeMenu(service)
        try controller.toggleRegistration()
        XCTAssertEqual(menu.items[0].state, .mixed)
        XCTAssertEqual(menu.items[0].title, "开机启动（等待系统允许）")
        XCTAssertFalse(menu.items[1].isHidden)
        XCTAssertTrue(controller.validateMenuItem(menu.items[1]))
        try controller.toggleRegistration()
        XCTAssertEqual(service.removals, 1)
        XCTAssertEqual(menu.items[0].state, .off)
        XCTAssertTrue(menu.items[1].isHidden)
    }

    func testExternalDisableAndApprovalAreRefreshedOnMenuOpen() {
        let service = Service()
        service.state = .enabled
        let (controller, menu) = makeMenu(service)
        service.state = .requiresApproval
        controller.menuWillOpen(menu)
        XCTAssertEqual(menu.items[0].state, .mixed)
        service.state = .disabled
        controller.menuWillOpen(menu)
        XCTAssertEqual(menu.items[0].state, .off)
        service.state = .enabled
        controller.menuWillOpen(menu)
        XCTAssertEqual(menu.items[0].state, .on)
        XCTAssertTrue(menu.items[1].isHidden)
        XCTAssertEqual(service.registrations, 0)
    }

    func testClickUsesCurrentStateNotStaleMenuCheckmark() throws {
        let service = Service()
        let (controller, _) = makeMenu(service)
        service.state = .enabled
        try controller.toggleRegistration()
        XCTAssertEqual(service.registrations, 0)
        XCTAssertEqual(service.removals, 1)
    }

    func testFailedEnableDoesNotShowEnabled() {
        let service = Service()
        service.fail = true
        let (controller, menu) = makeMenu(service)
        XCTAssertThrowsError(try controller.toggleRegistration())
        XCTAssertEqual(menu.items[0].state, .off)
    }

    func testFailedDisableRetainsActualEnabledState() {
        let service = Service()
        service.state = .enabled
        service.fail = true
        let (controller, menu) = makeMenu(service)
        XCTAssertThrowsError(try controller.toggleRegistration())
        XCTAssertEqual(menu.items[0].state, .on)
    }

    func testUnsupportedAndUnavailableStatesCannotBeRegistered() throws {
        for state in [LaunchAtLoginState.unsupported, .unavailable] {
            let service = Service()
            service.state = state
            let (controller, menu) = makeMenu(service)
            XCTAssertFalse(menu.items[0].isEnabled)
            XCTAssertFalse(controller.validateMenuItem(menu.items[0]))
            try controller.toggleRegistration()
            XCTAssertEqual(service.registrations, 0)
            XCTAssertEqual(service.removals, 0)
        }
    }

    func testRebuildBindsOnlyCurrentMenuItems() throws {
        let service = Service()
        let (controller, oldMenu) = makeMenu(service)
        let newMenu = NSMenu()
        controller.addMenuItems(to: newMenu)
        try controller.toggleRegistration()
        XCTAssertEqual(newMenu.items[0].state, .on)
        XCTAssertEqual(oldMenu.items[0].state, .off)
    }
}
