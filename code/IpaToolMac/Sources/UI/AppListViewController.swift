import AppKit
import SnapKit

final class AppListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onSelect: ((StoreApp?) -> Void)?
    var onActivate: ((StoreApp) -> Void)?
    var onVersions: ((StoreApp) -> Void)?

    var apps: [StoreApp] = [] {
        didSet { reload() }
    }

    var emptySymbol = "magnifyingglass"
    var emptyTitle = L10n.emptySearch
    var emptySubtitle = L10n.emptySearchHint

    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let empty = EmptyStateView()

    override func loadView() {
        view = NSView()

        table.headerView = nil
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.rowHeight = 80
        table.backgroundColor = .windowBackgroundColor
        table.style = .fullWidth
        table.selectionHighlightStyle = .regular
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        table.menu = makeMenu()
        table.intercellSpacing = .zero
        table.usesAlternatingRowBackgroundColors = false
        table.gridStyleMask = []
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true

        empty.configure(symbol: emptySymbol, title: emptyTitle, subtitle: emptySubtitle)

        view.addSubview(scroll)
        view.addSubview(empty)
        scroll.snp.makeConstraints { $0.edges.equalToSuperview() }
        empty.snp.makeConstraints { $0.edges.equalToSuperview() }
        reload()
    }

    func applyEmpty(symbol: String, title: String, subtitle: String) {
        emptySymbol = symbol
        emptyTitle = title
        emptySubtitle = subtitle
        empty.configure(symbol: symbol, title: title, subtitle: subtitle)
    }

    func selectedApp() -> StoreApp? {
        let row = table.selectedRow
        guard row >= 0, row < apps.count else { return nil }
        return apps[row]
    }

    func selectFirst() {
        guard !apps.isEmpty else { return }
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        onSelect?(apps[0])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { apps.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        InsetTableRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("AppCell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? AppTableCellView ?? AppTableCellView()
        cell.identifier = id
        let app = apps[row]
        cell.configure(app) { [weak self] in
            self?.onActivate?(app)
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        onSelect?(selectedApp())
        table.enumerateAvailableRowViews { rowView, _ in
            rowView.needsDisplay = true
        }
    }

    @objc private func doubleClicked() {
        if let app = selectedApp() { onActivate?(app) }
    }

    @objc private func downloadSelected() {
        if let app = selectedApp() { onActivate?(app) }
    }

    @objc private func versionsSelected() {
        if let app = selectedApp() { onVersions?(app) }
    }

    @objc private func copyBundleID() {
        guard let app = selectedApp() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(app.bundleID, forType: .string)
    }

    @objc private func copyAppID() {
        guard let app = selectedApp() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(app.id), forType: .string)
    }

    private func reload() {
        table.reloadData()
        let hasApps = !apps.isEmpty
        scroll.isHidden = !hasApps
        empty.isHidden = hasApps
        empty.configure(symbol: emptySymbol, title: emptyTitle, subtitle: emptySubtitle)
        if !hasApps { onSelect?(nil) }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.download, action: #selector(downloadSelected), keyEquivalent: "")
        menu.addItem(withTitle: L10n.versions, action: #selector(versionsSelected), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.copyBundleID, action: #selector(copyBundleID), keyEquivalent: "")
        menu.addItem(withTitle: L10n.copyAppID, action: #selector(copyAppID), keyEquivalent: "")
        return menu
    }
}

final class AppTableCellView: NSTableCellView {
    private let icon = AppIconView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let getButton = GetButton()
    private let separator = HairlineView()
    private var appID: Int64 = 0
    private var onGet: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        getButton.target = self
        getButton.action = #selector(getTapped)

        let text = NSStackView(views: [titleLabel, subtitleLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4

        addSubview(icon)
        addSubview(text)
        addSubview(getButton)
        addSubview(separator)

        icon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.centerY.equalToSuperview()
            make.size.equalTo(56)
        }
        text.snp.makeConstraints { make in
            make.leading.equalTo(icon.snp.trailing).offset(14)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(getButton.snp.leading).offset(-12)
        }
        getButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-20)
            make.centerY.equalToSuperview()
            make.height.equalTo(28)
            make.width.greaterThanOrEqualTo(64)
        }
        separator.snp.makeConstraints { make in
            make.leading.equalTo(text)
            make.trailing.equalToSuperview().offset(-20)
            make.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
        imageView = icon
        textField = titleLabel
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        separator.isHidden = (superview as? NSTableRowView)?.isSelected == true
    }

    func configure(_ app: StoreApp, onGet: @escaping () -> Void) {
        self.onGet = onGet
        appID = app.id
        titleLabel.stringValue = app.displayName
        subtitleLabel.stringValue = app.cellSubtitle
        getButton.setTitle(app.getTitle)
        icon.image = ArtworkStore.shared.placeholder(named: app.displayName)
        Task { [weak self] in
            let image = await ArtworkStore.shared.image(for: app.id, bundleID: app.bundleID)
            guard let self, self.appID == app.id, let image else { return }
            self.icon.image = image
        }
    }

    @objc private func getTapped() {
        onGet?()
    }
}
