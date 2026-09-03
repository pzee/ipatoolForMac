import AppKit
import SnapKit

final class ContentHostViewController: NSViewController {
    let login = LoginViewController()
    let search = SearchViewController()
    let purchases = PurchasesViewController()
    let downloads = DownloadsViewController()
    private let statusBar = StatusBarView()
    private let container = NSView()
    private var current: NSViewController?

    override func loadView() {
        view = NSView()
        view.addSubview(container)
        view.addSubview(statusBar)
        statusBar.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(26)
        }
        container.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(statusBar.snp.top)
        }

        login.onSuccess = { [weak self] in
            self?.applyState()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(applyState), name: .sessionAccountDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyState), name: .sessionSectionDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyStatus), name: .sessionStatusDidChange, object: nil)
        applyState()
        applyStatus()
    }

    func handleSearch(_ query: String) {
        guard Session.shared.isLoggedIn else { return }
        switch Session.shared.section {
        case .search:
            search.performSearch(query)
        case .purchases:
            purchases.filter(query)
        case .downloads:
            downloads.filter(query)
        }
    }

    func refreshCurrent() {
        guard Session.shared.isLoggedIn else { return }
        switch Session.shared.section {
        case .search:
            break
        case .purchases:
            purchases.reload()
        case .downloads:
            break
        }
    }

    @objc private func applyState() {
        let next: NSViewController
        if Session.shared.isLoggedIn {
            switch Session.shared.section {
            case .search: next = search
            case .purchases: next = purchases
            case .downloads: next = downloads
            }
        } else {
            next = login
        }
        guard current !== next else { return }
        current?.view.removeFromSuperview()
        current?.removeFromParent()
        addChild(next)
        container.addSubview(next.view)
        next.view.snp.makeConstraints { $0.edges.equalToSuperview() }
        current = next
        if next === login {
            login.focusEmail()
        }
    }

    @objc private func applyStatus() {
        statusBar.apply(
            text: Session.shared.statusText,
            isError: Session.shared.statusIsError,
            busy: Session.shared.isBusy
        )
    }
}
