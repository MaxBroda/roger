import AppKit
import RogerCore

/// The menu bar: keep an eye on state and reach Roger from any app. The symbol
/// never changes — it is a landmark; state lives in its colour and the menu text.
@MainActor
final class StatusItemController {
    private static let symbolName = "dot.radiowaves.left.and.right"

    private let app: RogerApp
    private let statusItem: NSStatusItem
    private let statusLine = NSMenuItem(title: "Bereit", action: nil, keyEquivalent: "")
    private let hotkeyLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let languageItem = NSMenuItem(title: "Sprache", action: nil, keyEquivalent: "")

    var onOpenMainWindow: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onShowSetup: (() -> Void)?
    var onQuit: (() -> Void)?

    init(app: RogerApp) {
        self.app = app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        buildMenu()
        refresh()
    }

    /// One call instead of many setters — the service knows what currently holds.
    func refresh() {
        let label = app.statusLine
        let image = NSImage(systemSymbolName: Self.symbolName, accessibilityDescription: label)

        // Without a colour the symbol stays a template and follows the menu bar.
        // A colour breaks that, so only where it means something.
        if let tint = tint {
            statusItem.button?.image = image?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [tint])
            )
            statusItem.button?.image?.isTemplate = false
        } else {
            statusItem.button?.image = image
            statusItem.button?.image?.isTemplate = true
        }

        statusLine.title = label
        hotkeyLine.title = "\(KeyNames.description(of: app.hotkey))"
        rebuildLanguageMenu()
    }

    /// Only recording and failure earn colour — the rest lasts fractions of a second.
    private var tint: NSColor? {
        switch app.state {
        case .recording: .systemRed
        case .failed: .systemOrange
        default: nil
        }
    }

    private func rebuildLanguageMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let sorted = app.languages.sorted { $0.name < $1.name }
        let installed = sorted.filter(\.isInstalled)
        let downloadable = sorted.filter { !$0.isInstalled }

        for choice in installed { menu.addItem(item(for: choice)) }
        if !installed.isEmpty, !downloadable.isEmpty {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Zum Laden verfügbar", action: nil, keyEquivalent: "").isEnabled = false
        }
        for choice in downloadable { menu.addItem(item(for: choice)) }

        if app.languages.isEmpty {
            menu.addItem(withTitle: "Keine Sprache verfügbar", action: nil, keyEquivalent: "").isEnabled = false
        }

        languageItem.submenu = menu
        languageItem.isEnabled = !app.languages.isEmpty
        languageItem.title = app.activeLocale.map { "Sprache: \($0.nativeDisplayName)" } ?? "Sprache"
    }

    private func item(for choice: RogerApp.LanguageChoice) -> NSMenuItem {
        let item = NSMenuItem(title: choice.name, action: #selector(languageSelected(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = choice.locale
        item.state = app.activeLocale.map { choice.locale.matches($0) } == true ? .on : .off
        return item
    }

    private func buildMenu() {
        let menu = NSMenu()
        // Otherwise AppKit disables every item without its own action — including
        // the language item, which carries its entries in a submenu.
        menu.autoenablesItems = false

        statusLine.isEnabled = false
        hotkeyLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(hotkeyLine)
        menu.addItem(.separator())

        let open = NSMenuItem(title: "Roger öffnen", action: #selector(openMainWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        languageItem.isEnabled = false
        menu.addItem(languageItem)

        let settings = NSMenuItem(title: "Einstellungen …", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let setup = NSMenuItem(title: "Einrichtung …", action: #selector(setupSelected), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Roger beenden", action: #selector(quitSelected), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func languageSelected(_ sender: NSMenuItem) {
        guard let locale = sender.representedObject as? Locale else { return }
        app.select(language: locale)
    }

    @objc private func openMainWindow() { onOpenMainWindow?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func setupSelected() { onShowSetup?() }
    @objc private func quitSelected() { onQuit?() }
}
