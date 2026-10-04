import Cocoa
import FlutterMacOS
import multiview_desktop

@main
class AppDelegate: FlutterAppDelegate {
  private var menuObserver: NSObjectProtocol?

  /// Points macOS at the Window menu, so it fills in what it puts there for
  /// every app that has one: Fill, Center, Move & Resize, and the list of
  /// open windows.
  ///
  /// Flutter's menu bar never says which of its menus is the Windows menu,
  /// and it builds a whole new menu bar each time the Dart side changes it —
  /// so this cannot be done once. Any item being added to a menu is the cue;
  /// the check waits a turn of the run loop because Flutter fills its new
  /// menu bar before installing it. Assigning only a menu it has not seen
  /// yet is what stops macOS adding its own items from setting this off
  /// again.
  override func awakeFromNib() {
    super.awakeFromNib()
    menuObserver = NotificationCenter.default.addObserver(
      forName: NSMenu.didAddItemNotification,
      object: nil,
      queue: .main
    ) { _ in
      DispatchQueue.main.async { AppDelegate.adoptWindowsMenu() }
    }
  }

  private static func adoptWindowsMenu() {
    guard
      let windowMenu = NSApp.mainMenu?.items.first(where: { $0.title == "Window" })?.submenu,
      NSApp.windowsMenu !== windowMenu
    else { return }
    NSApp.windowsMenu = windowMenu
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return MultiviewDesktopPlugin.applicationShouldTerminateAfterLastWindowClosed()
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if MultiviewDesktopPlugin.applicationShouldHandleReopen(sender, hasVisibleWindows: flag) {
      return true
    }
    return super.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
