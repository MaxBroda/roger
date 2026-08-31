import AppKit
import RogerCore

/// Composition root: builds the app service, the windows and the menu bar and
/// wires them together. State lives in ``RogerApp``.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let app = RogerApp()

    private var statusItem: StatusItemController?
    private var hud: HUDPanel?
    private var mainWindow: MainWindowController?
    private var settings: SettingsWindowController?
    private var onboarding: OnboardingWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install(target: self)

        let hud = HUDPanel()
        self.hud = hud

        let statusItem = StatusItemController(app: app)
        statusItem.onOpenMainWindow = { [weak self] in self?.mainWindow?.present() }
        statusItem.onOpenSettings = { [weak self] in self?.settings?.present() }
        statusItem.onShowSetup = { [weak self] in self?.onboarding?.present() }
        statusItem.onQuit = { NSApplication.shared.terminate(nil) }
        self.statusItem = statusItem

        // Menu bar and HUD are AppKit and don't observe — they get called. The
        // SwiftUI windows read `RogerApp` directly.
        app.onStateChange = { [weak self] state in self?.hud?.render(state) }
        app.onSpectrum = { [weak self] bands in self?.hud?.render(bands: bands) }
        app.onStatusChange = { [weak self] in self?.statusItem?.refresh() }
        app.onMenuBarModeChange = { [weak self] in self?.refreshActivationPolicy() }

        let mainWindow = MainWindowController(app: app)
        mainWindow.onVisibilityWillChange = { [weak self] willShow in
            self?.windowVisibilityWillChange(to: willShow)
        }
        self.mainWindow = mainWindow

        let settings = SettingsWindowController(app: app)
        settings.onVisibilityWillChange = { [weak self] willShow in
            self?.windowVisibilityWillChange(to: willShow)
        }
        self.settings = settings

        let onboarding = OnboardingWindow()
        onboarding.onVisibilityWillChange = { [weak self] willShow in
            self?.windowVisibilityWillChange(to: willShow)
        }
        onboarding.onCompleted = { [weak self] in
            self?.app.startDictationStack()
            self?.mainWindow?.present()
        }
        self.onboarding = onboarding

        // History and dictionary stay readable even without permissions — except
        // in menu-bar-only mode, where staying out of sight is the point.
        if !app.isMenuBarOnly {
            mainWindow.present()
        }

        // Without this window there is no way to grant a missing permission.
        if onboarding.isComplete {
            app.startDictationStack()
        } else {
            onboarding.present()
        }

        refreshActivationPolicy()
    }

    /// Roger is a regular app exactly as long as one of its windows is open:
    /// without a Dock icon a window barely takes keyboard focus and cannot be
    /// recalled from the app switcher.
    private func refreshActivationPolicy() {
        let wantsBackground = app.isMenuBarOnly && !hasVisibleWindow
        NSApp.setActivationPolicy(wantsBackground ? .accessory : .regular)
    }

    private var hasVisibleWindow: Bool {
        mainWindow?.isVisible == true
            || settings?.isVisible == true
            || onboarding?.isVisible == true
    }

    private func windowVisibilityWillChange(to willShow: Bool) {
        guard app.isMenuBarOnly else { return }
        if willShow {
            // Before ordering front, or the window comes up without focus.
            NSApp.setActivationPolicy(.regular)
        } else {
            // `windowWillClose` runs before the window turns invisible — the check
            // would still count it.
            Task { @MainActor [weak self] in self?.refreshActivationPolicy() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        app.shutdown()
    }

    /// Keeps running when the window closes — the key must work from any app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindow?.present() }
        return true
    }

    @objc func showMainWindow(_ sender: Any?) {
        mainWindow?.present()
    }

    @objc func showSettings(_ sender: Any?) {
        settings?.present()
    }

    @objc func showOnboarding(_ sender: Any?) {
        onboarding?.present()
    }

    @objc func toggleDictation(_ sender: Any?) {
        app.toggleDictation()
    }

    @objc func revealDictionaryFile(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([app.dictionary.fileURL])
    }
}

