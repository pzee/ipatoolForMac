import AppKit
import SnapKit

final class VersionsSheetController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let app: StoreApp
    private var versions: [VersionInfo] = []
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: L10n.loadingVersions)

    init(app: StoreApp) {
        self.app = app
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(app.displayName) 的历史版本"
        super.init(window: window)
        setup()
        load()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        let content = NSView()
        window?.contentView = content

        let close = NSButton(title: L10n.close, target: self, action: #selector(closeSheet))
        close.bezelStyle = .roundRect
        close.controlSize = .small
        let title = NSTextField(labelWithString: window?.title ?? L10n.versions)
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        let head = NSView()
        head.addSubview(title)
        head.addSubview(close)
        title.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
        }
        close.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-16)
            make.centerY.equalToSuperview()
        }

        table.delegate = self
        table.dataSource = self
        table.rowHeight = 40
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        for (id, title, width) in [
            ("version", L10n.version, 120),
            ("date", L10n.releaseDate, 140),
            ("id", L10n.versionID, 160),
            ("action", "", 80)
        ] as [(String, String, CGFloat)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor

        let line = HairlineView()
        content.addSubview(head)
        content.addSubview(line)
        content.addSubview(scroll)
        content.addSubview(status)
        head.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(44)
        }
        line.snp.makeConstraints { make in
            make.top.equalTo(head.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(1)
        }
        status.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.bottom.equalToSuperview().offset(-10)
        }
        scroll.snp.makeConstraints { make in
            make.top.equalTo(line.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(status.snp.top).offset(-8)
        }
    }

    private func load() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let ids = try await Session.shared.service.listVersions(app: self.app)
                self.versions = ids.reversed().prefix(80).map { VersionInfo(versionID: $0, displayVersion: nil, releaseDate: nil) }
                self.table.reloadData()
                self.status.stringValue = "\(self.versions.count) 个版本"
                await self.loadMetadata()
            } catch {
                self.status.stringValue = error.localizedDescription
            }
        }
    }

    private func loadMetadata() async {
        for index in versions.indices.prefix(30) {
            let id = versions[index].versionID
            if let info = try? await Session.shared.service.versionMetadata(app: app, versionID: id) {
                versions[index] = info
                table.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(0..<table.numberOfColumns))
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { versions.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let info = versions[row]
        let identifier = tableColumn?.identifier.rawValue ?? ""
        if identifier == "action" {
            let button = NSButton(title: L10n.download, target: self, action: #selector(downloadVersion(_:)))
            button.bezelStyle = .roundRect
            button.controlSize = .small
            button.tag = row
            return button
        }
        let field = NSTextField(labelWithString: "")
        field.font = identifier == "id" ? .monospacedSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 12)
        field.lineBreakMode = .byTruncatingMiddle
        switch identifier {
        case "version":
            field.stringValue = info.displayVersion ?? "—"
        case "date":
            field.stringValue = info.releaseDate.map { Formatters.day.string(from: $0) } ?? "—"
        default:
            field.stringValue = info.versionID
        }
        return field
    }

    @objc private func downloadVersion(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < versions.count else { return }
        Session.shared.enqueueDownload(app: app, versionID: versions[row].versionID)
        closeSheet()
        Session.shared.selectSection(.downloads)
    }

    @objc private func closeSheet() {
        window?.sheetParent?.endSheet(window!)
    }
}
