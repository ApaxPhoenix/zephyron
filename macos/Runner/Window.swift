import Cocoa
import FlutterMacOS

class Window: NSWindow {
  override func awakeFromNib() {
    let controller = FlutterViewController()
    let frame = self.frame
    self.contentViewController = controller
    self.setFrame(frame, display: true)

    RegisterGeneratedPlugins(registry: controller)

    super.awakeFromNib()
  }
}
