import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppMenu.install()
        let controller = MainWindowController()
        mainWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task {
            await Session.shared.refreshAccount()
        }
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
}

enum AppMenu {
    static func install() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 IPA Tool", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 IPA Tool", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "删除", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let accountMenu = NSMenu(title: L10n.account)
        accountMenu.addItem(withTitle: L10n.signIn, action: #selector(MainWindowController.focusLogin(_:)), keyEquivalent: "l")
        accountMenu.addItem(withTitle: L10n.signOut, action: #selector(MainWindowController.signOutClicked(_:)), keyEquivalent: "")
        accountMenu.addItem(.separator())
        accountMenu.addItem(withTitle: "选择下载目录…", action: #selector(MainWindowController.changeFolderClicked(_:)), keyEquivalent: "o")
        let accountItem = NSMenuItem(title: L10n.account, action: nil, keyEquivalent: "")
        accountItem.submenu = accountMenu
        main.addItem(accountItem)

        let viewMenu = NSMenu(title: "显示")
        viewMenu.addItem(withTitle: L10n.search, action: #selector(MainWindowController.showSearch(_:)), keyEquivalent: "1")
        viewMenu.addItem(withTitle: L10n.purchases, action: #selector(MainWindowController.showPurchases(_:)), keyEquivalent: "2")
        viewMenu.addItem(withTitle: L10n.downloads, action: #selector(MainWindowController.showDownloads(_:)), keyEquivalent: "3")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: L10n.refresh, action: #selector(MainWindowController.refreshClicked(_:)), keyEquivalent: "r")
        let viewItem = NSMenuItem(title: "显示", action: nil, keyEquivalent: "")
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}
