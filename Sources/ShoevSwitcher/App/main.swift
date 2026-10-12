import AppKit

let application = NSApplication.shared
if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:)) {
    application.applicationIconImage = icon
}
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.setActivationPolicy(.regular)
application.run()
