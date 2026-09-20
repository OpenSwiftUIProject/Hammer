#if os(iOS)
import UIKit

// Custom Window to have proper simulation of presentation and dismissal lifecycle events
final class HammerWindow: UIWindow {
    private let hammerViewController = HammerViewController()

    override var safeAreaInsets: UIEdgeInsets {
        return .zero
    }

    var viewControllerHasAppeared: Bool {
        return self.hammerViewController.hasAppeared
    }

    init() {
        super.init(frame: UIScreen.main.bounds)
        self.rootViewController = self.hammerViewController

        if #available(iOS 13.0, *) {
            self.backgroundColor = .systemBackground
        } else {
            self.backgroundColor = .white
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func presentContained(_ viewController: UIViewController) {
        self.makeVisibleAndKey()
        self.hammerViewController.presentContained(viewController)
    }

    func dismissContained() {
        self.hammerViewController.dismissContained()
        self.removeFromScene(removeViewController: false)
    }
}

private final class HammerViewController: UIViewController {
    private let containerView = UIView()

    override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }
    override var prefersStatusBarHidden: Bool { true }

    var hasAppeared = false

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .clear
        self.containerView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.containerView)

        // We only activate the top and leading constraints to allow the content to size itself.
        NSLayoutConstraint.activate([
            self.containerView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.containerView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.containerView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.containerView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.hasAppeared = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.hasAppeared = false
    }

    func presentContained(_ viewController: UIViewController) {
        viewController.beginAppearanceTransition(true, animated: false)
        self.addChild(viewController)

        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        self.containerView.addSubview(viewController.view)
        NSLayoutConstraint.activate([
            viewController.view.topAnchor.constraint(equalTo: self.containerView.topAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: self.containerView.bottomAnchor),
            viewController.view.leadingAnchor.constraint(equalTo: self.containerView.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: self.containerView.trailingAnchor),
        ])

        viewController.didMove(toParent: self)
        viewController.endAppearanceTransition()
        self.view.layoutIfNeeded()
    }

    func dismissContained() {
        for viewController in self.children {
            viewController.beginAppearanceTransition(false, animated: false)
            viewController.willMove(toParent: nil)
            viewController.view.removeFromSuperview()
            viewController.removeFromParent()
            viewController.endAppearanceTransition()
        }
    }
}

extension UIWindow {
    func makeVisibleAndKey(file: StaticString = #file, line: UInt = #line) {
        self.addToMainSceneIfNeeded(file: file, line: line)
        self.makeKeyAndVisible()
    }

    func addToMainSceneIfNeeded(file: StaticString = #file, line: UInt = #line) {
        guard #available(iOS 13.0, *) else {
            return
        }

        guard self.windowScene == nil else {
            return
        }

        if let mainScene = UIScene.mainOrFirstConnectedScene {
            self.windowScene = mainScene
        } else {
            assertionFailure("Unable to find main scene", file: file, line: line)
        }
    }

    func removeFromScene(removeViewController: Bool = true) {
        self.isHidden = true

        if #available(iOS 13.0, *) {
            self.windowScene = nil
        }

        if removeViewController {
            self.rootViewController = nil
        }
    }
}

@available(iOS 13.0, *)
private extension UIScene {
    static var mainOrFirstConnectedScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.screen == UIScreen.main } ?? scenes.first
    }
}
#elseif os(macOS)
import AppKit

/// A reusable test window that receives events without taking application focus.
///
/// The window stays outside all screens by default. Set `HAMMER_SHOW_TEST_WINDOW=1`
/// or pass `showWindow: true` to display it while debugging.
@MainActor
public final class HammerWindow: NSWindow {
    private var isClosed = false

    // AppKit must treat this test surface as key to dispatch the first mouse down.
    // Keep this state local to the window instead of changing NSApplication.keyWindow.
    public override var isKeyWindow: Bool { !self.isClosed && self.isVisible }
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public init(size: CGSize,
                showWindow: Bool = ProcessInfo.processInfo.environment["HAMMER_SHOW_TEST_WINDOW"] == "1") {
        let screens = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        let origin = NSPoint(x: screens.minX - size.width - 100, y: screens.minY)
        super.init(contentRect: NSRect(origin: origin, size: size),
                   styleMask: showWindow ? [.titled] : [.borderless], backing: .buffered, defer: false)
        self.isReleasedWhenClosed = false
        self.animationBehavior = .none
        self.hasShadow = false
        self.isExcludedFromWindowsMenu = true
        self.title = "Hammer Tests"
        if showWindow {
            self.center()
            self.orderFront(nil)
        } else {
            self.orderBack(nil)
        }
    }

    public override func close() {
        // AppKit must stop observing this window as key before it is destroyed.
        self.isClosed = true
        super.close()
    }
}
#endif
