#if os(macOS)
import AppKit
import Hammer
import XCTest

@MainActor
final class AppKitEventGeneratorTests: XCTestCase {
    private static let window = HammerWindow(size: NSSize(width: 200, height: 200))

    func testClickRecognizerUsesExistingWindow() async throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let action = ActionRecorder()
        view.addGestureRecognizer(NSClickGestureRecognizer(target: action, action: #selector(action.record)))
        try await withWindow(view: view) { events in
            let windows = NSApp.windows
            try await events.mouseClick()
            try await events.waitUntil(action.count == 1, timeout: 1)
            XCTAssertEqual(NSApp.windows, windows)
            XCTAssertTrue(events.mainView === view)
            XCTAssertTrue(events.window === view.window)
        }
    }

    func testWindowReuseIsolatesContent() async throws {
        let firstView = NSView()
        let firstAction = ActionRecorder()
        firstView.addGestureRecognizer(NSClickGestureRecognizer(target: firstAction,
                                                               action: #selector(firstAction.record)))
        var firstWindow: NSWindow?
        try await withWindow(view: firstView) { events in
            firstWindow = events.window
            try await events.mouseClick()
            try await events.waitUntil(firstAction.count == 1, timeout: 1)
        }
        XCTAssertNil(firstView.window)

        let secondView = NSView()
        let secondAction = ActionRecorder()
        secondView.addGestureRecognizer(NSClickGestureRecognizer(target: secondAction,
                                                                action: #selector(secondAction.record)))
        try await withWindow(view: secondView) { events in
            XCTAssertTrue(events.window === firstWindow)
            try await events.mouseClick()
            try await events.waitUntil(secondAction.count == 1, timeout: 1)
            XCTAssertEqual(firstAction.count, 1)
        }
        XCTAssertNil(secondView.window)
    }

    func testClickPreservesApplicationKeyWindow() async throws {
        let previousKeyWindow = NSApp.keyWindow
        let view = NSView()
        let action = ActionRecorder()
        view.addGestureRecognizer(NSClickGestureRecognizer(target: action, action: #selector(action.record)))
        try await withWindow(view: view) { events in
            XCTAssertTrue(NSApp.keyWindow === previousKeyWindow)
            if ProcessInfo.processInfo.environment["HAMMER_SHOW_TEST_WINDOW"] != "1" {
                XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(events.window.frame) })
            }
            try await events.mouseClick()
            try await events.waitUntil(action.count == 1, timeout: 1)
            XCTAssertTrue(NSApp.keyWindow === previousKeyWindow)
        }
    }

    func testButtonTrackingLoopReceivesMouseUp() async throws {
        let action = ActionRecorder()
        let button = NSButton(title: "Click", target: action, action: #selector(action.record))
        try await withWindow(view: button) { events in
            try await events.mouseClick()
            XCTAssertEqual(action.count, 1)
        }
    }

    func testDoubleClickRecognizer() async throws {
        let view = NSView()
        let action = ActionRecorder()
        let recognizer = NSClickGestureRecognizer(target: action, action: #selector(action.record))
        recognizer.numberOfClicksRequired = 2
        view.addGestureRecognizer(recognizer)
        try await withWindow(view: view) { events in
            try await events.mouseDoubleClick()
            try await events.waitUntil(action.count == 1, timeout: 1)
        }
    }

    func testDoubleClickAfterPanelResignsKey() async throws {
        let previousKeyWindow = NSApp.keyWindow
        let panel = NSPanel(contentRect: Self.window.frame, styleMask: [.titled, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.orderBack(nil)
        panel.makeKey()
        defer {
            panel.close()
            previousKeyWindow?.makeKey()
        }
        // A non-key panel requires first-mouse acceptance on macOS 15.
        let view = FirstMouseAcceptingView()
        let action = ActionRecorder()
        let recognizer = NSClickGestureRecognizer(target: action, action: #selector(action.record))
        recognizer.numberOfClicksRequired = 2
        view.addGestureRecognizer(recognizer)
        try await withWindow(view: view, window: panel) { events in
            try await events.mouseClick()
            events.window.resignKey()
            XCTAssertFalse(events.window.isKeyWindow)
            XCTAssertFalse(events.isWindowReady)
            do {
                try await events.mouseClick()
                XCTFail("Expected a window readiness error for a new click")
            } catch HammerError.windowIsNotReadyForInteraction {}
            try await events.wait(EventGenerator.multiClickInterval)
            try await events.mouseDown(clickCount: 2)
            try await events.wait(EventGenerator.mouseLiftDelay)
            try await events.mouseUp()
            try await events.waitUntil(action.count == 1, timeout: 1)
        }
    }

    func testNonKeyWindowCannotContinueClick() async throws {
        let window = NSWindow(
            contentRect: Self.window.frame,
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.orderBack(nil)
        window.resignKey()
        let events = try EventGenerator(window: window)
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(events.isWindowReady)
        do {
            try await events.mouseDown(clickCount: 2)
            XCTFail("Expected a window readiness error")
        } catch HammerError.windowIsNotReadyForInteraction {}
    }

    func testDragRecognizer() async throws {
        let view = NSView()
        let action = ActionRecorder()
        let recognizer = NSPanGestureRecognizer(target: action, action: #selector(action.record))
        view.addGestureRecognizer(recognizer)
        try await withWindow(view: view) { events in
            try await events.mouseDrag(
                from: RelativeLocation(location: view, x: 0.25, y: 0.5),
                to: RelativeLocation(location: view, x: 0.75, y: 0.5),
                duration: 0.1
            )
            try await events.waitUntil(action.states.contains(.ended), timeout: 1)
            XCTAssertTrue(action.states.contains(.began))
        }
    }

    func testLocationsInFlippedSubview() async throws {
        let root = NSView()
        let view = MouseRecorder(frame: NSRect(x: 30, y: 40, width: 120, height: 100))
        root.addSubview(view)
        try await withWindow(view: root) { events in
            try await events.mouseClick(at: RelativeLocation(location: view, x: 0.25, y: 0.75))
            XCTAssertEqual(view.locations, [NSPoint(x: 30, y: 75), NSPoint(x: 30, y: 75)])
        }
    }

    func testLongPressRecognizer() async throws {
        let view = NSView()
        let action = ActionRecorder()
        let recognizer = NSPressGestureRecognizer(target: action, action: #selector(action.record))
        recognizer.minimumPressDuration = 0.05
        view.addGestureRecognizer(recognizer)
        try await withWindow(view: view) { events in
            try await events.mouseLongPress(duration: 0.15)
            try await events.waitUntil(action.states.contains(.ended), timeout: 1)
            XCTAssertTrue(action.states.contains(.began))
        }
    }

    func testCoveredViewDoesNotClickTheOverlay() async throws {
        let root = NSView()
        let view = MouseRecorder(frame: NSRect(x: 30, y: 40, width: 120, height: 100))
        let overlay = MouseRecorder(frame: view.frame)
        root.addSubview(view)
        root.addSubview(overlay)
        try await withWindow(view: root) { events in
            do {
                try await events.mouseClick(at: view)
                XCTFail("Expected a covered view error")
            } catch HammerError.viewIsNotHittable {}
            XCTAssertTrue(view.types.isEmpty)
            XCTAssertTrue(overlay.types.isEmpty)
        }
    }

    func testLocationsInUnflippedSubview() async throws {
        let root = NSView()
        let view = MouseRecorder(frame: NSRect(x: 30, y: 40, width: 120, height: 100))
        view.usesFlippedCoordinates = false
        root.addSubview(view)
        try await withWindow(view: root) { events in
            try await events.mouseClick(at: RelativeLocation(location: view, x: 0.25, y: 0.75))
            XCTAssertEqual(view.locations, [NSPoint(x: 30, y: 25), NSPoint(x: 30, y: 25)])
        }
    }

    func testFailedDragReleasesMouse() async throws {
        let view = MouseRecorder()
        try await withWindow(view: view) { events in
            do {
                try await events.mouseDrag(to: NSView(), duration: 0.1)
                XCTFail("Expected a detached view error")
            } catch HammerError.viewIsNotInHierarchy {}
            XCTAssertEqual(view.types, [.leftMouseDown, .leftMouseUp])
            try await events.mouseClick()
            XCTAssertEqual(view.types.count, 4)
        }
    }

    func testCancellationExitsButtonTrackingLoop() async throws {
        let button = NSButton(title: "Click", target: nil, action: nil)
        try await withWindow(view: button) { events in
            let task = Task { try await events.mouseLongPress(duration: 10) }
            try await events.waitUntil(button.isHighlighted, timeout: 1)
            task.cancel()
            do {
                try await task.value
                XCTFail("Expected cancellation")
            } catch is CancellationError {}
            XCTAssertFalse(button.isHighlighted)
            try await events.mouseClick()
        }
    }

    func testCancellationReleasesMouse() async throws {
        let view = MouseRecorder()
        try await withWindow(view: view) { events in
            let task = Task { try await events.mouseLongPress(duration: 10) }
            try await events.waitUntil(view.types.contains(.leftMouseDown), timeout: 1)
            task.cancel()
            do {
                try await task.value
                XCTFail("Expected cancellation")
            } catch is CancellationError {}
            XCTAssertEqual(view.types, [.leftMouseDown, .leftMouseUp])
            try await events.mouseClick()
            XCTAssertEqual(view.types, [.leftMouseDown, .leftMouseUp, .leftMouseDown, .leftMouseUp])
        }
    }

    func testRejectsDetachedAndForeignViews() async throws {
        XCTAssertThrowsError(try EventGenerator(view: NSView()))
        try await withWindow(view: NSView()) { events in
            let other = HammerWindow(size: NSSize(width: 200, height: 200), showWindow: false)
            defer { other.close() }
            let view = NSView()
            other.contentView = view
            XCTAssertThrowsError(try view.windowHitPoint(for: events))
        }
    }

    func testTimeoutAndInvalidDuration() async throws {
        try await withWindow(view: NSView()) { events in
            do {
                try await events.waitUntil(false, timeout: 0.01)
                XCTFail("Expected timeout")
            } catch HammerError.waitConditionTimeout {}
            do {
                try await events.mouseLongPress(duration: .nan)
                XCTFail("Expected invalid duration")
            } catch HammerError.invalidDuration {}
            try await events.mouseClick()
        }
    }

}

extension AppKitEventGeneratorTests {
    func testClicksOnViewsThatRejectFirstMouse() async throws {
        for clickCount in [1, 2] {
            let root = FirstMouseRejectingView()
            let child = FirstMouseRejectingView(frame: NSRect(x: 20, y: 20, width: 100, height: 100))
            root.addSubview(child)
            let action = ActionRecorder()
            let recognizer = NSClickGestureRecognizer(target: action, action: #selector(action.record))
            recognizer.numberOfClicksRequired = clickCount
            root.addGestureRecognizer(recognizer)

            try await withWindow(view: root) { events in
                let wasActive = NSApp.isActive
                let keyWindow = NSApp.keyWindow
                XCTAssertFalse(root.acceptsFirstMouse(for: nil))
                XCTAssertFalse(child.acceptsFirstMouse(for: nil))
                try await events.mouseClick(at: child, numberOfTimes: clickCount)
                try await events.waitUntil(action.count == 1, timeout: 1)
                XCTAssertEqual(NSApp.isActive, wasActive)
                XCTAssertTrue(NSApp.keyWindow === keyWindow)
            }
        }
    }
}

private extension AppKitEventGeneratorTests {
    func withWindow(
        view: NSView,
        window: NSWindow? = nil,
        body: (EventGenerator) async throws -> Void
    ) async throws {
        let window = window ?? Self.window
        window.contentView = view
        window.setContentSize(NSSize(width: 200, height: 200))
        defer {
            window.makeFirstResponder(nil)
            window.contentView = nil
        }
        let events = try EventGenerator(view: view)
        try await events.waitUntilWindowIsReady()
        do {
            try await body(events)
        } catch {
            try? await events.mouseUp()
            throw error
        }
        try? await events.mouseUp()
    }
}

@MainActor
private final class ActionRecorder: NSObject {
    var count = 0
    var states: [NSGestureRecognizer.State] = []

    @objc func record(_ sender: Any) {
        count += 1
        if let recognizer = sender as? NSGestureRecognizer {
            states.append(recognizer.state)
        }
    }
}

@MainActor
private final class FirstMouseAcceptingView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class FirstMouseRejectingView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
}

@MainActor
private final class MouseRecorder: NSView {
    var types: [NSEvent.EventType] = []
    var locations: [NSPoint] = []
    var usesFlippedCoordinates = true
    override var isFlipped: Bool { usesFlippedCoordinates }

    override func mouseDown(with event: NSEvent) { record(event) }
    override func mouseUp(with event: NSEvent) { record(event) }
    override func mouseDragged(with event: NSEvent) { record(event) }

    private func record(_ event: NSEvent) {
        types.append(event.type)
        locations.append(convert(event.locationInWindow, from: nil))
    }
}
#endif
