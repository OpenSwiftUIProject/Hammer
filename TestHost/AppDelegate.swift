#if os(iOS)
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    {
        return true
    }
}
#elseif os(macOS)
import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {}
#endif
