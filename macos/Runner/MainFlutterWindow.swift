import Cocoa
import FlutterMacOS
import multiview_desktop

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let engine = FlutterEngine(
        name: "main_flutter_engine",
        project: nil,
        allowHeadlessExecution: true
    )
    MultiviewDesktopPlugin.prepareEngine(engine, window: self)

    let flutterViewController = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController

    // The IDE chrome is a three-pane layout with a toolbar row that stops
    // fitting below ~580pt wide. Nothing else prevents the window from being
    // dragged smaller, so the floor is set here rather than left to the user
    // to discover as a rendering glitch.
    self.contentMinSize = NSSize(width: 800, height: 600)
    self.setFrame(windowFrame, display: false)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
