import AppKit

final class MainWindowController: NSWindowController, NSToolbarDelegate, NSSearchFieldDelegate {
    private let sidebar = SidebarViewController()
    private let host = ContentHostViewController()
    private let split = NSSplitViewController()
    private let popover = NSPopover()
    private let accountPopover = AccountPopoverController()
    private var searchField: NSSearchField?
    private var accountItem: NSToolbarItem?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 880, height: 560)
        window.title = L10n.appName
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.backgroundColor = .windowBackgroundColor
        self.init(window: window)

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 240
        sidebarItem.canCollapse = true
        let contentItem = NSSplitViewItem(viewController: host)
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(contentItem)
        window.contentViewController = split
        restoreDefaultFrame()

        sidebar.onSelect = { section in
            guard Session.shared.isLoggedIn else {
                Session.shared.setStatus("请先登录", error: true, busy: false)
                return
            }
            Session.shared.selectSection(section)
        }
        sidebar.onSignOut = {
            Task { await Session.shared.signOut() }
        }

        popover.contentViewController = accountPopover
        popover.behavior = .transient

        setupToolbar()
        NotificationCenter.default.addObserver(self, selector: #selector(accountChanged), name: .sessionAccountDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sectionChanged), name: .sessionSectionDidChange, object: nil)
    }

    override func showWindow(_ sender: Any?) {
        restoreDefaultFrame()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func focusLogin(_ sender: Any?) {
        host.login.focusEmail()
        showWindow(nil)
    }

    private func restoreDefaultFrame() {
        guard let window else { return }
        var frame = window.frame
        if frame.height < 400 || frame.width < 700 {
            frame.size = NSSize(width: 1100, height: 700)
            if let screen = NSScreen.main?.visibleFrame {
                frame.origin.x = screen.midX - frame.width / 2
                frame.origin.y = screen.midY - frame.height / 2
            }
            window.setFrame(frame, display: true)
        }
        window.center()
    }

    @objc func signOutClicked(_ sender: Any?) {
        Task { await Session.shared.signOut() }
    }

    @objc func changeFolderClicked(_ sender: Any?) {
        Session.shared.chooseDownloadFolder(from: window)
    }

    @objc func showSearch(_ sender: Any?) {
        guard Session.shared.isLoggedIn else { return }
        Session.shared.selectSection(.search)
    }

    @objc func showPurchases(_ sender: Any?) {
        guard Session.shared.isLoggedIn else { return }
        Session.shared.selectSection(.purchases)
    }

    @objc func showDownloads(_ sender: Any?) {
        guard Session.shared.isLoggedIn else { return }
        Session.shared.selectSection(.downloads)
    }

    @objc func refreshClicked(_ sender: Any?) {
        host.refreshCurrent()
    }

    @objc private func submitSearch(_ sender: NSSearchField) {
        host.handleSearch(sender.stringValue)
    }

    @objc private func toggleAccount(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        accountPopover.refresh()
        guard let anchor = (sender as? NSView) ?? accountItem?.view else { return }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    @objc private func accountChanged() {
        sidebar.applyAccount(Session.shared.account)
        accountItem?.label = Session.shared.account?.name ?? L10n.account
        updateSearchPlaceholder()
    }

    @objc private func sectionChanged() {
        sidebar.select(Session.shared.section)
        updateSearchPlaceholder()
    }

    private func updateSearchPlaceholder() {
        switch Session.shared.section {
        case .search:
            searchField?.placeholderString = L10n.searchPlaceholder
        default:
            searchField?.placeholderString = L10n.filterPlaceholder
        }
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, .flexibleSpace, .searchField, .folder, .account]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, .flexibleSpace, .searchField, .folder, .account]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .sidebarTrackingSeparator:
            return NSTrackingSeparatorToolbarItem(
                identifier: .sidebarTrackingSeparator,
                splitView: split.splitView,
                dividerIndex: 0
            )
        case .searchField:
            let item = NSSearchToolbarItem(itemIdentifier: .searchField)
            item.searchField.placeholderString = L10n.searchPlaceholder
            item.searchField.target = self
            item.searchField.action = #selector(submitSearch(_:))
            searchField = item.searchField
            return item
        case .folder:
            let item = NSToolbarItem(itemIdentifier: .folder)
            item.image = Symbol.image("folder", size: 16)
            item.label = L10n.downloadFolder
            item.toolTip = L10n.chooseDownloadFolder
            item.target = self
            item.action = #selector(changeFolderClicked(_:))
            item.isBordered = true
            return item
        case .account:
            let button = NSButton()
            button.image = Symbol.image("person.crop.circle", size: 15)
            button.bezelStyle = .toolbar
            button.isBordered = true
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(toggleAccount(_:))
            button.toolTip = L10n.account

            let item = NSToolbarItem(itemIdentifier: .account)
            item.label = L10n.account
            item.toolTip = L10n.account
            item.view = button
            item.isBordered = true
            accountItem = item
            return item
        default:
            return nil
        }
    }
}

private extension NSToolbarItem.Identifier {
    static let searchField = NSToolbarItem.Identifier("searchField")
    static let folder = NSToolbarItem.Identifier("folder")
    static let account = NSToolbarItem.Identifier("account")
}
