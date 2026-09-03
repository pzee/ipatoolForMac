import AppKit
import SnapKit

final class PurchasesViewController: NSViewController {
    let list = AppListViewController()
    let inspector = InspectorViewController()

    private var page = 1
    private var total = 0
    private var allApps: [StoreApp] = []
    private let countLabel = NSTextField(labelWithString: "")
    private let prevButton = NSButton(title: L10n.previous, target: nil, action: nil)
    private let nextButton = NSButton(title: L10n.next, target: nil, action: nil)
    private var loaded = false

    override func loadView() {
        view = NSView()
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        prevButton.bezelStyle = .roundRect
        nextButton.bezelStyle = .roundRect
        prevButton.controlSize = .small
        nextButton.controlSize = .small
        prevButton.target = self
        nextButton.target = self
        prevButton.action = #selector(previousPage)
        nextButton.action = #selector(nextPage)

        let pager = NSStackView(views: [prevButton, nextButton])
        pager.spacing = 6
        let header = NSView()
        header.addSubview(countLabel)
        header.addSubview(pager)
        countLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.centerY.equalToSuperview()
        }
        pager.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-14)
            make.centerY.equalToSuperview()
        }

        let split = NSSplitViewController()
        let listItem = NSSplitViewItem(contentListWithViewController: list)
        listItem.minimumThickness = 280
        let inspectorItem = NSSplitViewItem(viewController: inspector)
        inspectorItem.minimumThickness = 260
        inspectorItem.maximumThickness = 360
        inspectorItem.holdingPriority = NSLayoutConstraint.Priority(260)
        split.addSplitViewItem(listItem)
        split.addSplitViewItem(inspectorItem)

        addChild(split)
        view.addSubview(header)
        view.addSubview(split.view)
        header.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(44)
        }
        split.view.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }

        list.applyEmpty(symbol: "bag", title: L10n.emptyPurchases, subtitle: L10n.emptyPurchasesHint)
        list.onSelect = { [weak self] app in self?.inspector.show(app) }
        list.onActivate = { app in
            Session.shared.enqueueDownload(app: app)
            Session.shared.selectSection(.downloads)
        }
        list.onVersions = { [weak self] app in self?.presentVersions(app) }
        inspector.onDownload = list.onActivate
        inspector.onVersions = { [weak self] app in self?.presentVersions(app) }
        inspector.onLicense = { app in
            Task {
                do {
                    let owned = try await Session.shared.service.purchase(bundleID: app.bundleID)
                    Session.shared.setStatus(owned ? L10n.alreadyOwned : L10n.licenseObtained, error: false, busy: false)
                } catch {
                    Session.shared.setStatus(error.localizedDescription, error: true, busy: false)
                }
            }
        }
        updatePager()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if !loaded {
            loaded = true
            reload()
        }
    }

    func reload() {
        Session.shared.setStatus(L10n.loadingPurchases, error: false, busy: true)
        let current = page
        Task {
            do {
                let result = try await Session.shared.service.listPurchases(page: current)
                allApps = result.apps
                total = result.totalCount
                list.apps = result.apps
                countLabel.stringValue = String(format: L10n.pageFormat, result.page, result.count, result.totalCount)
                Session.shared.setStatus(L10n.ready, error: false, busy: false)
                list.selectFirst()
                updatePager()
            } catch {
                Session.shared.setStatus(error.localizedDescription, error: true, busy: false)
            }
        }
    }

    func filter(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else {
            list.apps = allApps
            return
        }
        list.apps = allApps.filter {
            $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q)
        }
    }

    @objc private func previousPage() {
        guard page > 1 else { return }
        page -= 1
        reload()
    }

    @objc private func nextPage() {
        page += 1
        reload()
    }

    private func updatePager() {
        prevButton.isEnabled = page > 1
        nextButton.isEnabled = page * 20 < max(total, 1)
    }

    private func presentVersions(_ app: StoreApp) {
        guard let window = view.window else { return }
        let sheet = VersionsSheetController(app: app)
        window.beginSheet(sheet.window!) { _ in }
        objc_setAssociatedObject(window, Unmanaged.passUnretained(self).toOpaque(), sheet, .OBJC_ASSOCIATION_RETAIN)
    }
}
