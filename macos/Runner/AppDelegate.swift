import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    // Register URL event handler early, before Flutter plugins are loaded.
    // The app_links plugin's handler registration fires too late.
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
      forEventClass: AEEventClass(kInternetEventClass),
      andEventID: AEEventID(kAEGetURL)
    )
    NSLog("[DeepLink] Apple Event handler registered")
    super.applicationWillFinishLaunching(notification)
  }

  @objc func handleURLEvent(
    _ event: NSAppleEventDescriptor,
    withReplyEvent replyEvent: NSAppleEventDescriptor
  ) {
    guard let urlString = event.paramDescriptor(
      forKeyword: AEKeyword(keyDirectObject)
    )?.stringValue else {
      NSLog("[DeepLink] Apple Event received but no URL string")
      return
    }

    NSLog("[DeepLink] URL received: %@", urlString)

    // Store in UserDefaults - Dart reads via SharedPreferences on resume
    UserDefaults.standard.set(urlString, forKey: "flutter.pending_deep_link")
    UserDefaults.standard.synchronize()

    // Post a notification so the app can react immediately
    NotificationCenter.default.post(
      name: NSNotification.Name("DeepLinkReceived"),
      object: nil,
      userInfo: ["url": urlString]
    )
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
