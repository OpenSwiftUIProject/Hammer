#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import CoreGraphics
import Foundation

#if os(iOS)
@MainActor
private enum Storage {
    static var latestEventId: UInt32 = 0
}

#endif

/// Generates user interaction events for tests.
///
/// On macOS, the caller owns the window, its content, and application activation.
/// Run interactions serially on the main actor.
@MainActor
public final class EventGenerator {
    #if os(iOS)
    typealias CompletionHandler = @MainActor () -> Void

    public enum WrappingAlignment {
        /// Expand to fill the full available space
        case fill

        /// Center inside the available space
        case center
    }

    /// The window for the events
    public let window: UIWindow

    /// The view that was used to create the event generator
    public let mainView: UIView

    var activeTouches = TouchStorage()
    var debugWindow = DebugVisualizerWindow()
    var eventCallbacks = [UInt32: CompletionHandler]()

    // Deferred cleanup can run after the generator's address is reused.
    private let eventRegistrationID = UUID()

    /// The default sender id for all events.
    ///
    /// Can be any value except 0.
    public var senderId: UInt64 = 0x0000000123456789

    /// If the generated touches should be displayed over the view.
    public var showTouches: Bool {
        get { self.debugWindow.isHidden == false }
        set { self.debugWindow.isHidden = !newValue }
    }

    /// Initialize an event generator for a specified UIWindow.
    ///
    /// - parameter window:   The window to receive events.
    /// - parameter mainView: The view that was used to create the event generator
    private init(window: UIWindow, mainView: UIView) throws {
        self.window = window
        self.mainView = mainView
        self.window.layoutIfNeeded()
        self.debugWindow.frame = self.window.frame

        UIApplication.swizzle()
        UIApplication.registerForHIDEvents(self.eventRegistrationID) { [weak self] event in
            self?.markerEventReceived(event)
        }
    }

    /// Initialize an event generator for a specified UIWindow.
    ///
    /// - parameter window: The window to receive events.
    public convenience init(window: UIWindow) throws {
        try self.init(window: window, mainView: window)
        try self.waitUntilWindowIsReady()
    }

    /// Initialize an event generator for a specified UIViewController.
    ///
    /// If the view controller's view does not have a window, this will temporarily create a wrapper
    /// UIWindow to send touches.
    ///
    /// - parameter viewController: The viewController to receive events.
    public convenience init(viewController: UIViewController) throws {
        if let window = viewController.view.window  {
            try self.init(window: window, mainView: viewController.view)
        } else {
            let window = HammerWindow()
            window.presentContained(viewController)
            try self.init(window: window, mainView: viewController.view)
        }

        try self.waitUntilWindowIsReady()
    }

    /// Initialize an event generator for a specified UIView.
    ///
    /// If the view does not have a window, this will temporarily create a wrapper UIWindow to send touches.
    ///
    /// - parameter view:      The view to receive events.
    /// - parameter alignment: The wrapping alignment to use.
    public convenience init(view: UIView, alignment: WrappingAlignment = .center) throws {
        if let window = view.window {
            try self.init(window: window, mainView: view)
        } else {
            let viewController = UIViewController(wrapping: view.topLevelView, alignment: alignment)
            let window = HammerWindow()
            window.presentContained(viewController)
            try self.init(window: window, mainView: view)
        }

        try self.waitUntilWindowIsReady()
    }

    deinit {
        // The last reference can be released off the main actor. Retain the windows until cleanup runs.
        let cleanup: @MainActor @Sendable () -> Void = { [eventRegistrationID, debugWindow, window] in
            UIApplication.unregisterForHIDEvents(eventRegistrationID)
            debugWindow.removeFromScene()
            if let window = window as? HammerWindow {
                window.dismissContained()
            }
        }
        if #available(iOS 13.0, *), Thread.isMainThread {
            MainActor.assumeIsolated(cleanup)
        } else {
            DispatchQueue.main.async(execute: cleanup)
        }
    }

    /// Waits until the window is ready to receive user interaction events.
    ///
    /// - parameter timeout: The maximum time to wait for the window to be ready.
    public func waitUntilWindowIsReady(timeout: TimeInterval = 3) throws {
        do {
            try self.waitUntil(self.isWindowReady, timeout: timeout)
            try self.waitUntilAccessibilityActivate()

            if EventGenerator.settings.waitForFrameRender {
                try self.waitUntilFrameIsRendered(timeout: timeout)
            }

            if EventGenerator.settings.waitForAnimations {
                try self.waitUntilAnimationsAreFinished(timeout: timeout)
            }

            try self.waitUntilRunloopIsFlushed(timeout: timeout)
        } catch {
            throw HammerError.windowIsNotReadyForInteraction
        }
    }

    /// Waits until animations are finished.
    ///
    /// - parameter timeout: The maximum time to wait for the window to be ready.
    public func waitUntilAnimationsAreFinished(timeout: TimeInterval) throws {
        try self.waitUntil(!self.hasRunningAnimations, timeout: timeout)
    }

    /// Returns if the window is ready to receive user interaction events
    public var isWindowReady: Bool {
        guard !(UIApplication.shared as UIApplicationDeprecated).isIgnoringInteractionEvents
                && self.window.isHidden == false
                && self.window.isUserInteractionEnabled
                && self.window.rootViewController?.viewIfLoaded != nil
                && self.window.rootViewController?.isBeingPresented == false
                && self.window.rootViewController?.isBeingDismissed == false
                && self.window.rootViewController?.isMovingToParent == false
                && self.window.rootViewController?.isMovingFromParent == false else
        {
            return false
        }

        if #available(iOS 13.0, *) {
            guard self.window.windowScene?.activationState == .foregroundActive else {
                return false
            }
        }

        if let hammerWindow = self.window as? HammerWindow, !hammerWindow.viewControllerHasAppeared {
            return false
        }

        return true
    }

    // Returns if the view or any of its subviews has running animations.
    public var hasRunningAnimations: Bool {
        // Recursive
        func hasRunningAnimations(currentView: UIView) -> Bool {
            // If the view is not visible, we do not need to consider it as running animation
            guard self.viewIsVisible(currentView) else {
                return false
            }

            // If there are animations running on the layer, return true
            if currentView.layer.animationKeys()?.isEmpty == false {
                return true
            }

            // Special case for parallax dimming view which happens during some animations
            if String(describing: type(of: currentView)) == "_UIParallaxDimmingView" {
                return true
            }

            // Traverse subviews
            return currentView.subviews.contains { hasRunningAnimations(currentView: $0) }
        }

        return hasRunningAnimations(currentView: self.window)
    }

    /// Gets the next event ID to use. Event IDs are global and sequential.
    ///
    /// - returns: The next event ID.
    func nextEventId() -> UInt32 {
        Storage.latestEventId += 1
        return Storage.latestEventId
    }

    /// Sends a user interaction event.
    ///
    /// - parameter event: The event to send.
    /// - parameter wait:  If we should wait until the event has finished being sent.
    func sendEvent(_ event: IOHIDEvent, wait: Bool) throws {
        guard let window = self.window as? UIWindow & UIWindowPrivate else {
            throw HammerError.unableToAccessPrivateApi(type: "UIWindow", method: "Protocol")
        }

        guard let app = UIApplication.shared as? UIApplication & UIApplicationPrivate else {
            throw HammerError.unableToAccessPrivateApi(type: "UIApplication", method: "Protocol")
        }

        BackBoardServices.shared.eventSetDigitizerInfo(event, window.contextId, false, false, nil, 0, 0)

        app.enqueue(event)

        if wait {
            try self.waitForEvents()
        }
    }

    // MARK: - Sleep

    /// Sleeps the current thread until the events have finished sending.
    private func waitForEvents() throws {
        let waiter = Waiter(timeout: 1)
        try self.sendMarkerEvent { try? waiter.complete() }
        try waiter.start()
    }

    // MARK: - Accessibility initialization

    private var isAccessibilityActivated = false

    private func waitUntilAccessibilityActivate() throws {
        guard EventGenerator.settings.forceActivateAccessibilityEngine else {
            return
        }

        UIApplication.shared.accessibilityActivate()
        if self.isAccessibilityActivated {
            return
        }

        // The first time the accessibility engine is activated in a simulator it needs more time to warm up
        // and start producing consistent results, after that only a short delay per test case is enough
        let simAccessibilityActivatedKey = "accessibility_activated"
        let simAccessibilityActivated = UserDefaults.standard.bool(forKey: simAccessibilityActivatedKey)
        if !simAccessibilityActivated {
            print("Activating accessibility engine for the first time in this simulator and waiting 5s")
        } else {
            print("Activating accessibility engine and waiting 0.1s")
        }

        try self.wait(
            simAccessibilityActivated
            ? EventGenerator.settings.accessibilityActivateDelay // Default: 0.02s
            : EventGenerator.settings.accessibilityActivateFirstTimeDelay // Default: 5.0s
        )

        self.isAccessibilityActivated = true
        if !simAccessibilityActivated {
            UserDefaults.standard.set(true, forKey: simAccessibilityActivatedKey)
        }
    }
    #elseif os(macOS)
    public let window: NSWindow
    public let mainView: NSView

    nonisolated public static let mouseLiftDelay: TimeInterval = 0.05
    nonisolated public static let multiClickInterval: TimeInterval = 0.15
    nonisolated public static let longPressHoldDelay: TimeInterval = 2
    nonisolated public static let mouseMoveInterval: TimeInterval = 1 / 60

    private struct MousePress {
        var location: CGPoint
        let modifiers: NSEvent.ModifierFlags
        let eventNumber: Int
        let clickCount: Int
    }

    private static var latestEventNumber = 0
    private var mousePress: MousePress?
    private var isSendingMouseDown = false
    private var trackingMouseUp: CheckedContinuation<Void, Never>?

    /// Uses a view that is already attached to a window. Does not create or activate a window.
    public init(view: NSView) throws {
        guard let window = view.window else {
            throw HammerError.viewIsNotInHierarchy(view)
        }
        self.window = window
        self.mainView = view
    }

    public convenience init(viewController: NSViewController) throws {
        try self.init(view: viewController.view)
    }

    public convenience init(window: NSWindow) throws {
        guard let view = window.contentView else {
            throw HammerError.windowIsNotReadyForInteraction
        }
        try self.init(view: view)
    }

    public var isWindowReady: Bool {
        return self.hasVisibleWindowContent && self.window.isKeyWindow
    }

    private var hasVisibleWindowContent: Bool {
        return self.window.isVisible
            && self.mainView.window === self.window && !self.mainView.isHiddenOrHasHiddenAncestor
            && !self.mainView.visibleRect.isEmpty
    }

    public func waitUntilWindowIsReady(timeout: TimeInterval = 3) async throws {
        do {
            try await self.waitUntil(self.isWindowReady, timeout: timeout)
        } catch HammerError.waitConditionTimeout {
            throw HammerError.windowIsNotReadyForInteraction
        }
        self.mainView.layoutSubtreeIfNeeded()
        self.window.displayIfNeeded()
    }

    /// Sends a left mouse down. Locations use window coordinates; nil uses the view's center.
    public func mouseDown(at location: HammerLocatable? = nil, clickCount: Int = 1,
                          modifiers: NSEvent.ModifierFlags = []) async throws {
        try Task.checkCancellation()
        // A nonactivating panel can finish a multi-click sequence after it loses keyboard focus.
        let canContinueClick = clickCount > 1 && self.window.styleMask.contains(.nonactivatingPanel)
        guard self.hasVisibleWindowContent && (self.window.isKeyWindow || canContinueClick) else {
            throw HammerError.windowIsNotReadyForInteraction
        }
        guard self.mousePress == nil else { throw HammerError.mouseIsAlreadyDown }
        guard clickCount > 0 else { throw HammerError.invalidClickCount(clickCount) }
        let point = try (location ?? self.mainView).windowHitPoint(for: self)
        guard point.x.isFinite, point.y.isFinite, self.hitView(at: point) != nil else {
            throw HammerError.pointIsNotHittable(point)
        }
        EventGenerator.latestEventNumber &+= 1
        let press = MousePress(location: point, modifiers: modifiers,
                               eventNumber: EventGenerator.latestEventNumber, clickCount: clickCount)
        let event = try self.event(type: .leftMouseDown, press: press)
        self.mousePress = press
        await self.sendEvent(event)
    }

    /// Releases the left mouse button, including when the calling task is cancelled.
    public func mouseUp() async throws {
        guard let press = self.mousePress else { throw HammerError.mouseIsNotDown }
        let event = try self.event(type: .leftMouseUp, press: press)
        self.mousePress = nil
        await self.sendEvent(event)
    }

    /// Moves a held mouse button to a location. The destination may be outside the starting view.
    public func mouseMove(to location: HammerLocatable) async throws {
        try Task.checkCancellation()
        guard var press = self.mousePress else { throw HammerError.mouseIsNotDown }
        let point = try location.windowHitPoint(for: self)
        guard point.x.isFinite, point.y.isFinite else { throw HammerError.pointIsNotHittable(point) }
        let previousLocation = press.location
        press.location = point
        var event = try self.event(type: .leftMouseDragged, press: press)
        if let cgEvent = event.cgEvent {
            cgEvent.setDoubleValueField(.mouseEventDeltaX, value: point.x - previousLocation.x)
            cgEvent.setDoubleValueField(.mouseEventDeltaY, value: previousLocation.y - point.y)
            if let movedEvent = NSEvent(cgEvent: cgEvent) { event = movedEvent }
        }
        self.mousePress = press
        await self.sendEvent(event)
    }

    /// Interpolates a held mouse button's position over the specified duration.
    public func mouseMove(to location: HammerLocatable, duration: TimeInterval) async throws {
        try Self.validateDuration(duration)
        guard let start = self.mousePress?.location else { throw HammerError.mouseIsNotDown }
        let end = try location.windowHitPoint(for: self)
        let started = ProcessInfo.processInfo.systemUptime
        while duration > 0 {
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            guard elapsed < duration else { break }
            let fraction = elapsed / duration
            try await self.mouseMove(to: CGPoint(x: start.x + (end.x - start.x) * fraction,
                                                y: start.y + (end.y - start.y) * fraction))
            try await self.wait(min(Self.mouseMoveInterval, duration - elapsed))
        }
        try await self.mouseMove(to: end)
    }

    /// Clicks with the left mouse button. Multiple clicks carry increasing AppKit click counts.
    public func mouseClick(at location: HammerLocatable? = nil, numberOfTimes count: Int = 1,
                           interval: TimeInterval = EventGenerator.multiClickInterval,
                           modifiers: NSEvent.ModifierFlags = []) async throws {
        guard count > 0 else { throw HammerError.invalidClickCount(count) }
        try Self.validateDuration(interval)
        for index in 0..<count {
            try await self.withMouseDown(at: location, clickCount: index + 1, modifiers: modifiers) {
                try await self.wait(Self.mouseLiftDelay)
            }
            if index < count - 1 { try await self.wait(interval) }
        }
    }

    public func mouseDoubleClick(at location: HammerLocatable? = nil,
                                 interval: TimeInterval = EventGenerator.multiClickInterval,
                                 modifiers: NSEvent.ModifierFlags = []) async throws {
        try await self.mouseClick(at: location, numberOfTimes: 2, interval: interval, modifiers: modifiers)
    }

    public func mouseLongPress(at location: HammerLocatable? = nil,
                               duration: TimeInterval = EventGenerator.longPressHoldDelay,
                               modifiers: NSEvent.ModifierFlags = []) async throws {
        try Self.validateDuration(duration)
        try await self.withMouseDown(at: location, modifiers: modifiers) {
            try await self.wait(duration)
        }
    }

    public func mouseDrag(from start: HammerLocatable? = nil, to end: HammerLocatable,
                          duration: TimeInterval, modifiers: NSEvent.ModifierFlags = []) async throws {
        try Self.validateDuration(duration)
        try await self.withMouseDown(at: start, modifiers: modifiers) {
            try await self.mouseMove(to: end, duration: duration)
        }
    }

    private func withMouseDown(at location: HammerLocatable?, clickCount: Int = 1,
                               modifiers: NSEvent.ModifierFlags,
                               body: () async throws -> Void) async throws {
        try await self.mouseDown(at: location, clickCount: clickCount, modifiers: modifiers)
        do {
            try await body()
        } catch {
            try? await self.mouseUp()
            throw error
        }
        try await self.mouseUp()
    }

    private func event(type: NSEvent.EventType, press: MousePress) throws -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type, location: press.location, modifierFlags: press.modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: self.window.windowNumber,
            context: nil, eventNumber: press.eventNumber, clickCount: press.clickCount,
            pressure: type == .leftMouseUp ? 0 : 1
        ) else {
            throw HammerError.couldNotCreateMouseEvent
        }
        return event
    }

    private func sendEvent(_ event: NSEvent) async {
        await withCheckedContinuation { continuation in
            // Start dispatch outside a main queue job. A control can enter a nested tracking loop
            // in mouseDown; the suspended test must be able to resume there and send mouseUp.
            let dispatch: @MainActor @Sendable () -> Void = {
                if RunLoop.current.currentMode == .eventTracking {
                    // Tracking controls read from nextEvent instead of NSApplication.sendEvent.
                    NSApp.postEvent(event, atStart: false)
                    if event.type == .leftMouseUp && self.isSendingMouseDown {
                        self.trackingMouseUp = continuation
                    } else {
                        continuation.resume()
                    }
                } else {
                    continuation.resume()
                    if event.type == .leftMouseDown { self.isSendingMouseDown = true }
                    NSApp.sendEvent(event)
                    if event.type == .leftMouseDown {
                        self.isSendingMouseDown = false
                        // Return from mouseUp only after the tracking control has finished.
                        self.trackingMouseUp?.resume()
                        self.trackingMouseUp = nil
                    }
                }
            }
            RunLoop.main.perform(inModes: [.default, .eventTracking]) {
                MainActor.assumeIsolated(dispatch)
            }
        }
    }
    #endif
}

#if os(iOS)
// Bypasses deprecation warning for `isIgnoringInteractionEvents`
private protocol UIApplicationDeprecated {
    var isIgnoringInteractionEvents: Bool { get }
}

extension UIApplication: UIApplicationDeprecated {}
#endif
