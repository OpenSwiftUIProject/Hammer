#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@MainActor
public protocol HammerLocatable {
    func windowHitPoint(for eventGenerator: EventGenerator) throws -> CGPoint
}

extension CGPoint: HammerLocatable {
    public func windowHitPoint(for eventGenerator: EventGenerator) throws -> CGPoint {
        return self
    }
}

extension CGRect: HammerLocatable {
    public func windowHitPoint(for eventGenerator: EventGenerator) throws -> CGPoint {
        return self.center
    }
}

#if os(macOS)
extension NSView: HammerLocatable {
    public func windowHitPoint(for eventGenerator: EventGenerator) throws -> CGPoint {
        return try eventGenerator.windowHitPoint(forView: self)
    }
}

extension NSViewController: HammerLocatable {
    public func windowHitPoint(for eventGenerator: EventGenerator) throws -> CGPoint {
        return try self.view.windowHitPoint(for: eventGenerator)
    }
}
#elseif os(iOS)
extension UIView: HammerLocatable {
    public func windowHitPoint(for eventGenerator: EventGenerator) throws -> CGPoint {
        return try eventGenerator.windowHitPoint(forView: self)
    }
}

extension UIViewController: HammerLocatable {
    public func windowHitPoint(for eventGenerator: EventGenerator) throws -> CGPoint {
        return try self.view.windowHitPoint(for: eventGenerator)
    }
}
#endif

extension String: HammerLocatable {
    public func windowHitPoint(for eventGenerator: EventGenerator) throws -> CGPoint {
        return try eventGenerator.viewWithIdentifier(self).windowHitPoint(for: eventGenerator)
    }
}

/// Creates an absolute offset for a location in window coordinates.
/// Positive y moves down on iOS and up on macOS.
public struct OffsetLocation: HammerLocatable {
    public let location: HammerLocatable?
    public let x: CGFloat
    public let y: CGFloat

    /// Creates an offset for a location.
    ///
    /// - parameter location: The location to offset. Passing nil will use the default location.
    /// - parameter x:        The x offset.
    /// - parameter y:        The y offset.
    public init(location: HammerLocatable? = nil, x: CGFloat, y: CGFloat) {
        self.location = location
        self.x = x
        self.y = y
    }

    public func windowHitPoint(for eventGenerator: EventGenerator) throws -> CGPoint {
        let location = self.location ?? eventGenerator.mainView
        let hitPoint = try location.windowHitPoint(for: eventGenerator)
        return hitPoint.offset(x: self.x, y: self.y)
    }
}

/// Creates a relative location for a view.
public struct RelativeLocation: HammerLocatable {
    #if os(macOS)
    public let view: NSView?
    #elseif os(iOS)
    public let view: UIView?
    #endif
    public let x: CGFloat
    public let y: CGFloat

    #if os(macOS)
    /// Uses fractions of the view's bounds, from the top left (0, 0) to the bottom right (1, 1).
    /// Values outside this range can be used to drag outside the view. Nil uses the default view.
    public init(location view: NSView? = nil, x: CGFloat, y: CGFloat) {
        self.view = view
        self.x = x
        self.y = y
    }
    #elseif os(iOS)
    /// Creates a relative location for a view
    ///
    /// Values for x and y are relative to the dimensions of the view. From 0 to 1, 0 being the top/left of
    /// the view and 1 being the bottom/right of the view. Passing a value outside those bounds will result
    /// in the touch occurring outside the view.
    ///
    /// - parameter view: The view to get a relative location for. Passing nil will use the default view.
    /// - parameter x:    The relative x value.
    /// - parameter y:    The relative y value.
    public init(location view: UIView? = nil, x: CGFloat, y: CGFloat) {
        self.view = view
        self.x = x
        self.y = y
    }
    #endif

    public func windowHitPoint(for eventGenerator: EventGenerator) throws -> CGPoint {
        let view = self.view ?? eventGenerator.mainView
        #if os(macOS)
        try eventGenerator.validateView(view)
        let bounds = view.bounds
        let point = CGPoint(x: bounds.minX + bounds.width * self.x,
                            y: view.isFlipped ? bounds.minY + bounds.height * self.y
                                             : bounds.maxY - bounds.height * self.y)
        return view.convert(point, to: nil)
        #else
        let hitPoint = try eventGenerator.windowHitPoint(forView: view)
        return CGPoint(x: hitPoint.x - view.bounds.center.x + view.bounds.width * self.x,
                       y: hitPoint.y - view.bounds.center.y + view.bounds.height * self.y)
        #endif
    }
}
