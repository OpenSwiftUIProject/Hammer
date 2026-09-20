#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// https://github.com/lyft/Hammer#troubleshooting.
public enum HammerError: Error {
    case windowIsNotReadyForInteraction

    #if os(iOS)
    case windowIsNotKey

    case deviceDoesNotSupportTouches
    case deviceDoesNotSupportStylus

    case touchForFingerAlreadyExists(index: FingerIndex)
    case touchForFingerDoesNotExist(index: FingerIndex)
    case fingerLimitReached(limit: Int)
    case invalidFingerCount(count: Int, expected: Int)

    case touchForStylusAlreadyExists
    case touchForStylusDoesNotExist

    case unknownKeyForCharacter(Character)

    case unsupportedTouchPhase(UITouch.Phase)

    case unableToAccessPrivateApi(type: String, method: String)
    #endif

    #if os(macOS)
    case viewIsNotInHierarchy(NSView)
    case viewIsNotVisible(NSView)
    case viewIsNotHittable(NSView)
    #elseif os(iOS)
    case viewIsNotInHierarchy(UIView)
    case viewIsNotVisible(UIView)
    case viewIsNotHittable(UIView)
    #endif
    case pointIsNotHittable(CGPoint)

    case unableToFindView(identifier: String)
    #if os(iOS)
    case invalidViewType(identifier: String, type: String, expected: String)
    #endif
    case waitConditionTimeout(TimeInterval)

    #if os(iOS)
    case waiterIsNotRunning
    case waiterIsAlreadyRunning
    case waiterIsAlreadyCompleted
    #elseif os(macOS)
    case mouseIsAlreadyDown
    case mouseIsNotDown
    case couldNotCreateMouseEvent
    case invalidClickCount(Int)
    case invalidDuration(TimeInterval)
    #endif
}

extension HammerError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .windowIsNotReadyForInteraction:
            #if os(macOS)
            return "The window must be visible and key, with visible test content"
            #else
            return """
                The app or window is not ready for interaction. Ensure that your tests are running in a \
                host application and that you have given enough time for the view to present on screen. \
                For more troubleshooting tips see: https://github.com/lyft/Hammer#troubleshooting.
                """
            #endif
        #if os(iOS)
        case .windowIsNotKey:
            return "The window must be the key window to receive keyboard events"
        case .deviceDoesNotSupportTouches:
            return "Device does not support touches"
        case .deviceDoesNotSupportStylus:
            return "Device does not support stylus"
        case .touchForFingerAlreadyExists(let index):
            return "A touch for finger with index \(index) already exists"
        case .touchForFingerDoesNotExist(let index):
            return "A touch for finger with index \(index) does not exist"
        case .fingerLimitReached(let limit):
            return "The maximum number of fingers on the screen simultaneously has been exceeded (\(limit))"
        case .invalidFingerCount(let count, let expected):
            return "Invalid number of fingers, got \(count) expected \(expected)"
        case .touchForStylusAlreadyExists:
            return "A touch for the stylus already exists"
        case .touchForStylusDoesNotExist:
            return "A touch for the stylus does not exists"
        case .unknownKeyForCharacter(let character):
            return "Unknown keyboard mapping for character: \"\(character)\""
        case .unsupportedTouchPhase(let phase):
            return "Unsupported touch phase \(phase)"
        case .unableToAccessPrivateApi(let type, let method):
            return "Unable to access private API in \(type): \"\(method)\""
        case .viewIsNotInHierarchy(let view):
            return "View is not in hierarchy: \(view.shortDescription)"
        case .viewIsNotVisible(let view):
            return "View is not visible: \(view.shortDescription)"
        case .viewIsNotHittable(let view):
            return "View is not hittable: \(view.shortDescription)"
        #elseif os(macOS)
        case .viewIsNotInHierarchy:
            return "The view must be attached to the event generator's window"
        case .viewIsNotVisible:
            return "The view is not visible"
        case .viewIsNotHittable:
            return "The view cannot receive mouse events at its center"
        #endif
        case .pointIsNotHittable(let point):
            return "Point is not hittable: \(point)"
        case .unableToFindView(let identifier):
            return "Unable to find view: \"\(identifier)\""
        #if os(iOS)
        case .invalidViewType(let identifier, let type, let expected):
            return "Invalid type for view: \"\(identifier)\", got \"\(type)\" expected \"\(expected)\""
        #endif
        case .waitConditionTimeout(let timeout):
            return "Timeout while waiting for condition exceeded \(timeout) seconds"
        #if os(iOS)
        case .waiterIsNotRunning:
            return "Unable to stop a Waiter that is not running"
        case .waiterIsAlreadyRunning:
            return "Unable to start a Waiter that is already running"
        case .waiterIsAlreadyCompleted:
            return "Unable to start or stop a waiter that is already completed"
        #elseif os(macOS)
        case .mouseIsAlreadyDown:
            return "The left mouse button is already down"
        case .mouseIsNotDown:
            return "The left mouse button is not down"
        case .couldNotCreateMouseEvent:
            return "AppKit could not create a mouse event"
        case .invalidClickCount(let count):
            return "Click count must be positive: \(count)"
        case .invalidDuration(let duration):
            return "Invalid duration: \(duration)"
        #endif
        }
    }
}

#if os(iOS)
extension UIView {
    fileprivate var shortDescription: String {
        return self.accessibilityIdentifier ?? self.description
    }
}
#endif
