import AppKit
import SnapKit

final class SearchViewController: NSViewController {
    let list = AppListViewController()
    let inspector = InspectorViewController()
    private(set) var platform: AppPlatform = .iphone

    private let platforms = NSSegmentedControl(
        labels: AppPlatform.allCases.map(\.title),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let countLabel = NSTextField(labelWithString: L10n.emptySearchHint)

    override func loadView() {
        view = NSView()

        platforms.segmentStyle = .rounded
        platforms.selectedSegment = 0
        platforms.target = self
        platforms.action = #selector(platformChanged)
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor

        let header = NSView()
        header.addSubview(platforms)
        header.addSubview(countLabel)
        platforms.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.centerY.equalToSuperview()
        }
        countLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-14)
            make.centerY.equalToSuperview()
            make.leading.greaterThanOrEqualTo(platforms.snp.trailing).offset(12)
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

        list.applyEmpty(symbol: "magnifyingglass", title: L10n.emptySearch, subtitle: L10n.emptySearchHint)
        wire()
    }

    func performSearch(_ query: String) {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        let selected = platform
        Session.shared.setStatus(L10n.searching, error: false, busy: true)
        Task {
            do {
                let apps = try await Session.shared.service.search(term: term, platform: selected)
                list.apps = apps
                countLabel.stringValue = String(format: L10n.resultsFormat, apps.count)
                Session.shared.setStatus(String(format: L10n.resultsFormat, apps.count), error: false, busy: false)
                list.selectFirst()
            } catch {
                Session.shared.setStatus(error.localizedDescription, error: true, busy: false)
            }
        }
    }

    private func wire() {
        list.onSelect = { [weak self] app in
            self?.inspector.show(app)
        }
        list.onActivate = { app in
            Session.shared.enqueueDownload(app: app)
            Session.shared.selectSection(.downloads)
        }
        list.onVersions = { [weak self] app in
            self?.presentVersions(app)
        }
        inspector.onDownload = list.onActivate
        inspector.onVersions = { [weak self] app in
            self?.presentVersions(app)
        }
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
    }

    private func presentVersions(_ app: StoreApp) {
        guard let window = view.window else { return }
        let sheet = VersionsSheetController(app: app)
        window.beginSheet(sheet.window!) { _ in }
        objc_setAssociatedObject(window, Unmanaged.passUnretained(self).toOpaque(), sheet, .OBJC_ASSOCIATION_RETAIN)
    }

    @objc private func platformChanged() {
        let index = max(0, platforms.selectedSegment)
        platform = AppPlatform.allCases[index]
        inspector.show(list.selectedApp())
    }
}
