import AppKit
import SnapKit

final class DownloadsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private var jobs: [DownloadJob] = []
    private var filtered: [DownloadJob] = []
    private var filterText = ""
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let empty = EmptyStateView()
    private let pathLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        empty.configure(symbol: "arrow.down.circle", title: L10n.emptyDownloads, subtitle: L10n.emptyDownloadsHint)

        let caption = NSTextField(labelWithString: L10n.downloadFolder)
        caption.font = .systemFont(ofSize: 12, weight: .medium)
        caption.textColor = .secondaryLabelColor
        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let changeButton = NSButton(title: L10n.changeFolder, target: self, action: #selector(changeFolder))
        let revealButton = NSButton(title: L10n.revealFolder, target: self, action: #selector(revealFolder))
        changeButton.bezelStyle = .roundRect
        revealButton.bezelStyle = .roundRect
        changeButton.controlSize = .small
        revealButton.controlSize = .small

        let header = NSView()
        header.addSubview(caption)
        header.addSubview(pathLabel)
        header.addSubview(revealButton)
        header.addSubview(changeButton)
        caption.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
        }
        pathLabel.snp.makeConstraints { make in
            make.leading.equalTo(caption.snp.trailing).offset(8)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(revealButton.snp.leading).offset(-12)
        }
        changeButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-14)
            make.centerY.equalToSuperview()
        }
        revealButton.snp.makeConstraints { make in
            make.trailing.equalTo(changeButton.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
        }

        table.headerView = nil
        table.rowHeight = 64
        table.backgroundColor = .windowBackgroundColor
        table.style = .fullWidth
        table.selectionHighlightStyle = .regular
        table.delegate = self
        table.dataSource = self
        table.intercellSpacing = .zero
        table.gridStyleMask = []
        table.doubleAction = #selector(revealSelected)
        table.target = self
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("job")))

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let line = HairlineView()
        view.addSubview(header)
        view.addSubview(line)
        view.addSubview(scroll)
        view.addSubview(empty)
        header.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(44)
        }
        line.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(1)
        }
        scroll.snp.makeConstraints { make in
            make.top.equalTo(line.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
        empty.snp.makeConstraints { make in
            make.top.equalTo(line.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadFromSession),
            name: .sessionDownloadsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshPath),
            name: .sessionFolderDidChange,
            object: nil
        )
        refreshPath()
        reloadFromSession()
    }

    @objc private func changeFolder() {
        Session.shared.chooseDownloadFolder(from: view.window)
    }

    @objc private func revealFolder() {
        let folder = Session.shared.downloadFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func refreshPath() {
        pathLabel.stringValue = Formatters.homeRelative(Session.shared.downloadFolder)
    }

    func filter(_ query: String) {
        filterText = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        applyFilter()
    }

    @objc private func reloadFromSession() {
        jobs = Session.shared.downloads
        applyFilter()
    }

    private func applyFilter() {
        if filterText.isEmpty {
            filtered = jobs
        } else {
            filtered = jobs.filter {
                $0.appName.lowercased().contains(filterText) || $0.bundleID.lowercased().contains(filterText)
            }
        }
        table.reloadData()
        scroll.isHidden = filtered.isEmpty
        empty.isHidden = !filtered.isEmpty
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        InsetTableRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("DownloadCell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? DownloadTableCellView ?? DownloadTableCellView()
        cell.identifier = id
        cell.configure(filtered[row])
        return cell
    }

    @objc private func revealSelected() {
        let row = table.selectedRow
        guard row >= 0, row < filtered.count, let url = filtered[row].outputPath else { return }
        Session.shared.reveal(url)
    }
}

final class DownloadTableCellView: NSTableCellView {
    private let icon = AppIconView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let pill = StatusPillView()
    private var appID: Int64 = 0
    private var bundleID = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.layer?.cornerRadius = 9
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle

        let text = NSStackView(views: [titleLabel, pathLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        addSubview(icon)
        addSubview(text)
        addSubview(pill)
        icon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.centerY.equalToSuperview()
            make.size.equalTo(40)
        }
        text.snp.makeConstraints { make in
            make.leading.equalTo(icon.snp.trailing).offset(12)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(pill.snp.leading).offset(-12)
        }
        pill.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-20)
            make.centerY.equalToSuperview()
            make.height.equalTo(22)
            make.width.greaterThanOrEqualTo(56)
        }
        imageView = icon
        textField = titleLabel
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ job: DownloadJob) {
        appID = job.appID
        bundleID = job.bundleID
        titleLabel.stringValue = job.appName
        if let path = job.outputPath {
            pathLabel.stringValue = Formatters.homeRelative(path)
        } else {
            pathLabel.stringValue = job.errorMessage ?? job.bundleID
        }
        switch job.status {
        case .succeeded:
            pill.apply(title: job.status.title, textColor: NSColor(red: 0.14, green: 0.54, blue: 0.24, alpha: 1), background: NSColor.systemGreen.withAlphaComponent(0.16))
        case .running, .queued:
            pill.apply(title: job.status.title, textColor: .controlAccentColor, background: NSColor.controlAccentColor.withAlphaComponent(0.16))
        case .failed:
            pill.apply(title: job.status.title, textColor: .systemRed, background: NSColor.systemRed.withAlphaComponent(0.12))
        }
        icon.image = ArtworkStore.shared.placeholder(named: job.appName, size: 40)
        Task { [weak self] in
            let image = await ArtworkStore.shared.image(for: job.appID, bundleID: job.bundleID)
            guard let self, self.appID == job.appID, let image else { return }
            self.icon.image = image
        }
    }
}
