#if os(macOS)
import AppKit
import Hammer
import XCTest

@MainActor
final class AppKitEventGeneratorTests: XCTestCase {
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
            try await withWindow(view: NSView()) { other in
                XCTAssertThrowsError(try other.mainView.windowHitPoint(for: events))
            }
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

    private func withWindow(
        view: NSView,
        body: (EventGenerator) async throws -> Void
    ) async throws {
        let application = NSApplication.shared
        let previousKeyWindow = application.keyWindow
        // A nonactivating panel can receive events while the test host is in the background.
        let window = NSPanel(
            contentRect: NSRect(x: 200, y: 200, width: 200, height: 200),
            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.setContentSize(NSSize(width: 200, height: 200))
        defer {
            window.close()
            previousKeyWindow?.makeKey()
        }
        window.makeKeyAndOrderFront(nil)
        let events = try EventGenerator(view: view)
        try await events.waitUntilWindowIsReady()
        try await body(events)
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
