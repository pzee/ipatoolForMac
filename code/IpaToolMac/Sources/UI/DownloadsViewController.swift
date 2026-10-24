import AppKit
import SnapKit

final class DownloadsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation, NSMenuDelegate {
    private var jobs: [DownloadJob] = []
    private var filtered: [DownloadJob] = []
    private var filterText = ""
    private let table = DownloadTableView()
    private let scroll = NSScrollView()
    private let empty = EmptyStateView()
    private let pathLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton(title: L10n.deleteIPA, target: nil, action: nil)

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
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected)
        changeButton.bezelStyle = .roundRect
        revealButton.bezelStyle = .roundRect
        deleteButton.bezelStyle = .roundRect
        changeButton.controlSize = .small
        revealButton.controlSize = .small
        deleteButton.controlSize = .small
        deleteButton.isEnabled = false

        let header = NSView()
        header.addSubview(caption)
        header.addSubview(pathLabel)
        header.addSubview(deleteButton)
        header.addSubview(revealButton)
        header.addSubview(changeButton)
        caption.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
        }
        pathLabel.snp.makeConstraints { make in
            make.leading.equalTo(caption.snp.trailing).offset(8)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(deleteButton.snp.leading).offset(-12)
        }
        changeButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-14)
            make.centerY.equalToSuperview()
        }
        revealButton.snp.makeConstraints { make in
            make.trailing.equalTo(changeButton.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
        }
        deleteButton.snp.makeConstraints { make in
            make.trailing.equalTo(revealButton.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
        }

        table.headerView = nil
        table.rowHeight = 64
        table.backgroundColor = .windowBackgroundColor
        table.style = .fullWidth
        table.selectionHighlightStyle = .regular
        table.allowsMultipleSelection = true
        table.delegate = self
        table.dataSource = self
        table.intercellSpacing = .zero
        table.gridStyleMask = []
        table.doubleAction = #selector(revealSelected)
        table.target = self
        table.onDeleteKey = { [weak self] in self?.deleteSelected() }
        table.menu = makeMenu()
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
            selector: #selector(updateProgress(_:)),
            name: .sessionDownloadProgressDidChange,
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

    override func viewWillAppear() {
        super.viewWillAppear()
        Session.shared.pruneMissingDownloads()
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

    @objc private func updateProgress(_ notification: Notification) {
        guard let id = notification.userInfo?["jobID"] as? UUID,
              let job = Session.shared.downloads.first(where: { $0.id == id }) else { return }
        if let index = jobs.firstIndex(where: { $0.id == id }) { jobs[index] = job }
        guard let row = filtered.firstIndex(where: { $0.id == id }) else { return }
        filtered[row] = job
        (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? DownloadTableCellView)?.updateStatus(job)
    }

    private func applyFilter() {
        let selectedIDs = Set(table.selectedRowIndexes.compactMap { row in
            filtered.indices.contains(row) ? filtered[row].id : nil
        })
        if filterText.isEmpty {
            filtered = jobs
        } else {
            filtered = jobs.filter {
                $0.appName.lowercased().contains(filterText) || $0.bundleID.lowercased().contains(filterText)
            }
        }
        table.reloadData()
        table.selectRowIndexes(IndexSet(filtered.indices.filter { selectedIDs.contains(filtered[$0].id) }), byExtendingSelection: false)
        scroll.isHidden = filtered.isEmpty
        empty.isHidden = !filtered.isEmpty
        updateDeleteButton()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateDeleteButton()
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
        let jobID = filtered[row].id
        cell.onAction = {
            guard let job = Session.shared.downloads.first(where: { $0.id == jobID }) else { return }
            if job.canCancel { Session.shared.cancelDownload(jobID) }
            else if job.canRetry { Session.shared.retryDownload(jobID) }
        }
        return cell
    }

    @objc private func revealSelected() {
        guard let job = actionJobs().first, let url = job.outputPath, job.fileExists else { return }
        Session.shared.reveal(url)
    }

    @objc private func cancelSelected() {
        actionJobs().filter(\.canCancel).forEach { Session.shared.cancelDownload($0.id) }
    }

    @objc private func retrySelected() {
        actionJobs().filter(\.canRetry).forEach { Session.shared.retryDownload($0.id) }
    }

    @objc func delete(_ sender: Any?) {
        deleteSelected()
    }

    @objc private func deleteSelected() {
        let jobs = actionJobs().filter(\.canDelete)
        guard !jobs.isEmpty else { return }
        let hasFiles = jobs.contains(where: \.fileExists)
        let alert = NSAlert()
        if hasFiles {
            alert.messageText = L10n.deleteIPATitle
            if jobs.count == 1 {
                alert.informativeText = String(format: L10n.deleteIPAConfirmOne, jobs[0].appName)
            } else {
                alert.informativeText = String(format: L10n.deleteIPAConfirmMany, jobs.count)
            }
        } else {
            alert.messageText = L10n.removeFromListTitle
            alert.informativeText = L10n.removeFromListMessage
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: hasFiles ? L10n.deleteIPA : L10n.removeFromList)
        alert.addButton(withTitle: L10n.cancel)
        alert.buttons.first?.hasDestructiveAction = true
        let present: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            Session.shared.deleteDownloads(jobs.map(\.id))
        }
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: present)
        } else {
            present(alert.runModal())
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let jobs = actionJobs()
        switch menuItem.action {
        case #selector(revealSelected):
            return jobs.contains { $0.fileExists }
        case #selector(deleteSelected), #selector(delete(_:)):
            return jobs.contains(where: \.canDelete)
        case #selector(cancelSelected):
            return jobs.contains(where: \.canCancel)
        case #selector(retrySelected):
            return jobs.contains(where: \.canRetry)
        default:
            return true
        }
    }

    private func actionJobs() -> [DownloadJob] {
        let rows: IndexSet
        if table.clickedRow >= 0 {
            if table.selectedRowIndexes.contains(table.clickedRow) {
                rows = table.selectedRowIndexes
            } else {
                rows = IndexSet(integer: table.clickedRow)
            }
        } else {
            rows = table.selectedRowIndexes
        }
        return rows.compactMap { row in
            guard row >= 0, row < filtered.count else { return nil }
            return filtered[row]
        }
    }

    private func updateDeleteButton() {
        let jobs = table.selectedRowIndexes.compactMap { row -> DownloadJob? in
            guard row >= 0, row < filtered.count else { return nil }
            return filtered[row]
        }
        deleteButton.isEnabled = jobs.contains(where: \.canDelete)
        deleteButton.title = jobs.contains(where: \.fileExists) ? L10n.deleteIPA : L10n.removeFromList
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let jobs = actionJobs()
        if let item = menu.items.last {
            item.title = jobs.contains(where: \.fileExists) ? L10n.deleteIPA : L10n.removeFromList
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: L10n.showInFinder, action: #selector(revealSelected), keyEquivalent: "")
        menu.addItem(withTitle: L10n.cancelDownload, action: #selector(cancelSelected), keyEquivalent: "")
        menu.addItem(withTitle: L10n.retry, action: #selector(retrySelected), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.deleteIPA, action: #selector(deleteSelected), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }
}

final class DownloadTableView: NSTableView {
    var onDeleteKey: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.specialKey == .delete || event.specialKey == .deleteForward {
            onDeleteKey?()
            return
        }
        super.keyDown(with: event)
    }
}

final class DownloadTableCellView: NSTableCellView {
    var onAction: (() -> Void)?
    private let icon = AppIconView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let pill = StatusPillView()
    private let progressBar = NSProgressIndicator()
    private let actionButton = NSButton(title: "", target: nil, action: nil)
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
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        progressBar.style = .bar
        progressBar.controlSize = .small
        progressBar.maxValue = 100
        actionButton.bezelStyle = .roundRect
        actionButton.controlSize = .small
        actionButton.target = self
        actionButton.action = #selector(performAction)

        let text = NSStackView(views: [titleLabel, pathLabel, progressBar])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        addSubview(icon)
        addSubview(text)
        let actions = NSStackView(views: [pill, actionButton])
        actions.spacing = 8
        actions.setHuggingPriority(.required, for: .horizontal)
        addSubview(actions)
        icon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.centerY.equalToSuperview()
            make.size.equalTo(40)
        }
        text.snp.makeConstraints { make in
            make.leading.equalTo(icon.snp.trailing).offset(12)
            make.centerY.equalToSuperview()
            make.trailing.equalTo(actions.snp.leading).offset(-12)
        }
        actions.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-20)
            make.centerY.equalToSuperview()
        }
        progressBar.snp.makeConstraints { make in
            make.width.equalTo(text)
        }
        pill.snp.makeConstraints { make in
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
        titleLabel.stringValue = job.appName
        updateStatus(job)
        guard appID != job.appID || bundleID != job.bundleID || icon.image == nil else { return }
        appID = job.appID
        bundleID = job.bundleID
        icon.image = ArtworkStore.shared.placeholder(named: job.appName, size: 40)
        Task { [weak self] in
            let image = await ArtworkStore.shared.image(for: job.appID, bundleID: job.bundleID)
            guard let self, self.appID == job.appID, self.bundleID == job.bundleID, let image else { return }
            self.icon.image = image
        }
    }

    func updateStatus(_ job: DownloadJob) {
        actionButton.isHidden = !job.canCancel && !job.canRetry && !job.isCancelling
        actionButton.isEnabled = !job.isCancelling
        actionButton.title = job.canRetry ? L10n.retry : L10n.cancel
        actionButton.setAccessibilityLabel(job.canRetry ? L10n.retry : L10n.cancelDownload)
        progressBar.isHidden = job.status != .running
        progressBar.isIndeterminate = job.progress == nil || job.isCancelling
        progressBar.setAccessibilityLabel("\(L10n.downloading) \(job.appName)")
        if job.status == .running && progressBar.isIndeterminate {
            progressBar.startAnimation(nil)
        } else {
            progressBar.stopAnimation(nil)
            progressBar.doubleValue = Double(job.progress?.percent ?? 0)
        }
        if job.isCancelling {
            pathLabel.stringValue = L10n.cancelling
        } else if job.status == .running {
            if let progress = job.progress {
                pathLabel.stringValue = progress.percent == 100 ? L10n.processingDownload
                    : (progress.detail.isEmpty ? L10n.downloading : progress.detail)
            } else {
                pathLabel.stringValue = L10n.preparingDownload
            }
        } else if let path = job.outputPath {
            pathLabel.stringValue = Formatters.homeRelative(path)
        } else {
            pathLabel.stringValue = (job.errorMessage ?? job.bundleID).localized()
        }
        pathLabel.toolTip = pathLabel.stringValue
        let statusTitle = job.isCancelling ? L10n.cancelling
            : (job.status == .running ? job.progress.map { "\($0.percent)%" } ?? job.status.title : job.status.title)
        pill.setAccessibilityLabel(statusTitle)
        switch job.status {
        case .succeeded:
            pill.apply(title: job.status.title, textColor: NSColor(red: 0.14, green: 0.54, blue: 0.24, alpha: 1), background: NSColor.systemGreen.withAlphaComponent(0.16))
        case .running, .queued:
            pill.apply(title: statusTitle, textColor: .controlAccentColor, background: NSColor.controlAccentColor.withAlphaComponent(0.16))
        case .failed:
            pill.apply(title: job.status.title, textColor: .systemRed, background: NSColor.systemRed.withAlphaComponent(0.12))
        case .cancelled:
            pill.apply(title: job.status.title, textColor: .secondaryLabelColor, background: NSColor.labelColor.withAlphaComponent(0.08))
        }
    }

    @objc private func performAction() {
        onAction?()
    }
}
