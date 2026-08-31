import AppKit
import RogerCore

// Before `run()`, not in the delegate: macOS shows the Dock icon before
// `applicationDidFinishLaunching`, which would flash in menu-bar-only mode.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(MenuBarModePreference().isMenuBarOnly ? .accessory : .regular)
application.run()
