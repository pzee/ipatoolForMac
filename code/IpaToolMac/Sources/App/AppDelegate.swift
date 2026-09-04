import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppLanguage.apply()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .languageDidChange,
            object: nil
        )
        AppMenu.install()
        presentMainWindow()
        NSApp.activate(ignoringOtherApps: true)
        Task {
            await Session.shared.refreshAccount()
        }
    }

    @objc private func languageDidChange() {
        AppMenu.install()
        presentMainWindow()
        NotificationCenter.default.post(name: .sessionAccountDidChange, object: Session.shared)
        NotificationCenter.default.post(name: .sessionSectionDidChange, object: Session.shared)
        Task { @MainActor in
            Session.shared.setStatus(L10n.ready, error: false, busy: Session.shared.isBusy)
        }
    }

    private func presentMainWindow() {
        let previous = mainWindowController
        let controller = MainWindowController()
        mainWindowController = controller
        controller.showWindow(nil)
        previous?.close()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    @objc func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = AppLanguage(rawValue: raw) else { return }
        AppLanguage.select(language)
    }
}

enum AppMenu {
    static func install() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.aboutApp, action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.quitApp, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editMenu = NSMenu(title: L10n.edit)
        editMenu.addItem(withTitle: L10n.undo, action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: L10n.redo, action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.cut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.paste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.delete, action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.selectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: L10n.edit, action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let accountMenu = NSMenu(title: L10n.account)
        accountMenu.addItem(withTitle: L10n.signIn, action: #selector(MainWindowController.focusLogin(_:)), keyEquivalent: "l")
        accountMenu.addItem(withTitle: L10n.signOut, action: #selector(MainWindowController.signOutClicked(_:)), keyEquivalent: "")
        accountMenu.addItem(.separator())
        accountMenu.addItem(withTitle: L10n.chooseDownloadFolder, action: #selector(MainWindowController.changeFolderClicked(_:)), keyEquivalent: "o")
        let languageMenu = NSMenu(title: L10n.language)
        for language in AppLanguage.allCases {
            let item = NSMenuItem(title: language.title, action: #selector(AppDelegate.selectLanguage(_:)), keyEquivalent: "")
            item.representedObject = language.rawValue
            item.state = language == AppLanguage.current ? .on : .off
            languageMenu.addItem(item)
        }
        let languageItem = NSMenuItem(title: L10n.language, action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu
        accountMenu.addItem(languageItem)
        let accountItem = NSMenuItem(title: L10n.account, action: nil, keyEquivalent: "")
        accountItem.submenu = accountMenu
        main.addItem(accountItem)

        let viewMenu = NSMenu(title: L10n.view)
        viewMenu.addItem(withTitle: L10n.search, action: #selector(MainWindowController.showSearch(_:)), keyEquivalent: "1")
        viewMenu.addItem(withTitle: L10n.purchases, action: #selector(MainWindowController.showPurchases(_:)), keyEquivalent: "2")
        viewMenu.addItem(withTitle: L10n.downloads, action: #selector(MainWindowController.showDownloads(_:)), keyEquivalent: "3")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: L10n.refresh, action: #selector(MainWindowController.refreshClicked(_:)), keyEquivalent: "r")
        let viewItem = NSMenuItem(title: L10n.view, action: nil, keyEquivalent: "")
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        let windowMenu = NSMenu(title: L10n.window)
        windowMenu.addItem(withTitle: L10n.minimize, action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: L10n.zoom, action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        let windowItem = NSMenuItem(title: L10n.window, action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}
