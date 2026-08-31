import AppKit

/// Hand-built, because Roger is no Xcode project with a `MainMenu.xib`. Without
/// the Edit menu, ⌘C and ⌘V stop working in the app's text fields — the key
/// equivalents hang off the menu, not the field.
@MainActor
enum MainMenu {
    static func install(target: AnyObject) {
        let main = NSMenu()
        main.addItem(appMenu(target: target))
        main.addItem(editMenu())
        main.addItem(dictationMenu(target: target))
        main.addItem(windowMenu(target: target))
        NSApp.mainMenu = main
        NSApp.windowsMenu = main.items.last?.submenu
    }

    private static func appMenu(target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu()

        menu.addItem(
            withTitle: "Über Roger",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            entry("Einstellungen …", #selector(AppDelegate.showSettings(_:)), ",", target: target)
        )
        menu.addItem(
            entry("Einrichtung …", #selector(AppDelegate.showOnboarding(_:)), "", target: target)
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Roger ausblenden",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = NSMenuItem(
            title: "Andere ausblenden",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(
            withTitle: "Alle anzeigen",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Roger beenden",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        item.submenu = menu
        return item
    }

    private static func editMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Bearbeiten", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Bearbeiten")

        menu.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Löschen", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        item.submenu = menu
        return item
    }

    private static func dictationMenu(target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: "Diktat", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Diktat")
        menu.addItem(
            entry("Aufnahme starten oder beenden", #selector(AppDelegate.toggleDictation(_:)), "r", target: target)
        )
        menu.addItem(.separator())
        menu.addItem(
            entry("Wörterbuchdatei zeigen", #selector(AppDelegate.revealDictionaryFile(_:)), "", target: target)
        )
        item.submenu = menu
        return item
    }

    private static func windowMenu(target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: "Fenster", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Fenster")
        menu.addItem(
            entry("Roger", #selector(AppDelegate.showMainWindow(_:)), "0", target: target)
        )
        menu.addItem(.separator())
        menu.addItem(withTitle: "Fenster schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(withTitle: "Im Dock ablegen", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoomen", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Alle nach vorne bringen",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        item.submenu = menu
        return item
    }

    private static func entry(
        _ title: String,
        _ action: Selector,
        _ key: String,
        target: AnyObject
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}
