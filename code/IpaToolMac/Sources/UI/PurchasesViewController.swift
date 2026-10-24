import AppKit
import SnapKit

final class PurchasesViewController: NSViewController {
    let list = AppListViewController()
    let inspector = InspectorViewController()

    private var pagination = PurchasePagination()
    private var allApps: [StoreApp] = []
    private var filterText = ""
    private var loadTask: Task<Void, Never>?
    private var retryPage: Int?
    private var accountEmail: String?
    private let countLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let retryButton = NSButton(title: L10n.retry, target: nil, action: nil)
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
        retryButton.bezelStyle = .roundRect
        retryButton.controlSize = .small
        retryButton.target = self
        retryButton.action = #selector(retryLoading)
        retryButton.isHidden = true
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.setAccessibilityLabel(L10n.loadingPurchases)
        countLabel.lineBreakMode = .byTruncatingTail
        countLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let pager = NSStackView(views: [spinner, retryButton, prevButton, nextButton])
        pager.spacing = 6
        let header = NSView()
        header.addSubview(countLabel)
        header.addSubview(pager)
        countLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(pager.snp.leading).offset(-12)
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
        accountEmail = Session.shared.account?.email
        NotificationCenter.default.addObserver(self, selector: #selector(accountChanged), name: .sessionAccountDidChange, object: nil)
        updatePager()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if !loaded {
            reload()
        }
    }

    func reload() {
        loadPage(pagination.page)
    }

    private func loadPage(_ target: Int) {
        guard pagination.begin(target) else { return }
        retryPage = nil
        retryButton.title = L10n.cancel
        retryButton.toolTip = nil
        retryButton.isHidden = false
        countLabel.stringValue = String(format: L10n.loadingPage, target)
        spinner.startAnimation(nil)
        updatePager()
        Session.shared.setStatus(L10n.loadingPurchases, error: false, busy: true)
        loadTask = Task {
            do {
                let result = try await Session.shared.service.listPurchases(page: target)
                guard !Task.isCancelled else { return }
                pagination.finish(result)
                retryButton.isHidden = true
                loaded = true
                allApps = result.apps
                filter(filterText)
                countLabel.stringValue = String(format: L10n.pageFormat, result.page, result.count, result.totalCount)
                Session.shared.setStatus(L10n.ready, error: false, busy: false)
            } catch {
                guard !Task.isCancelled else { return }
                pagination.fail()
                retryPage = target
                retryButton.title = L10n.retry
                retryButton.isHidden = false
                retryButton.toolTip = error.localizedDescription
                countLabel.stringValue = loaded
                    ? String(format: L10n.pageFormat, pagination.page, allApps.count, pagination.total)
                    : L10n.failed
                Session.shared.setStatus(error.localizedDescription, error: true, busy: false)
            }
            spinner.stopAnimation(nil)
            updatePager()
            loadTask = nil
        }
    }

    func filter(_ query: String) {
        filterText = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        list.apps = filterText.isEmpty ? allApps : allApps.filter {
            $0.name.lowercased().contains(filterText) || $0.bundleID.lowercased().contains(filterText)
        }
        list.selectFirst()
    }

    @objc private func previousPage() {
        guard pagination.canGoBack else { return }
        loadPage(pagination.page - 1)
    }

    @objc private func nextPage() {
        guard pagination.canGoForward else { return }
        loadPage(pagination.page + 1)
    }

    @objc private func retryLoading() {
        if pagination.isLoading {
            retryPage = pagination.loadingPage
            loadTask?.cancel()
            loadTask = nil
            pagination.fail()
            retryButton.title = L10n.retry
            spinner.stopAnimation(nil)
            countLabel.stringValue = loaded
                ? String(format: L10n.pageFormat, pagination.page, allApps.count, pagination.total)
                : L10n.cancelled
            updatePager()
            Session.shared.setStatus(L10n.ready, error: false, busy: false)
            return
        }
        if let retryPage { loadPage(retryPage) }
    }

    @objc private func accountChanged() {
        guard accountEmail != Session.shared.account?.email else { return }
        accountEmail = Session.shared.account?.email
        loadTask?.cancel()
        loadTask = nil
        pagination = PurchasePagination()
        loaded = false
        retryPage = nil
        retryButton.isHidden = true
        allApps = []
        list.apps = []
        countLabel.stringValue = ""
        spinner.stopAnimation(nil)
        updatePager()
        if view.window != nil, Session.shared.isLoggedIn { reload() }
    }

    private func updatePager() {
        prevButton.isEnabled = pagination.canGoBack
        nextButton.isEnabled = pagination.canGoForward
    }

    private func presentVersions(_ app: StoreApp) {
        guard let window = view.window else { return }
        let sheet = VersionsSheetController(app: app)
        window.beginSheet(sheet.window!) { _ in }
        objc_setAssociatedObject(window, Unmanaged.passUnretained(self).toOpaque(), sheet, .OBJC_ASSOCIATION_RETAIN)
    }
}
