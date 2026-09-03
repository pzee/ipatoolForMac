import AppKit
import SnapKit

final class InspectorViewController: NSViewController {
    var onDownload: ((StoreApp) -> Void)?
    var onLicense: ((StoreApp) -> Void)?
    var onVersions: ((StoreApp) -> Void)?

    private var app: StoreApp?
    private var appID: Int64 = 0

    private let empty = EmptyStateView()
    private let content = NSView()
    private let iconView = AppIconView()
    private let nameLabel = NSTextField(wrappingLabelWithString: "")
    private let bundleLabel = NSTextField(labelWithString: "")
    private let idValue = NSTextField(labelWithString: "")
    private let versionValue = NSTextField(labelWithString: "")
    private let priceValue = NSTextField(labelWithString: "")
    private let platformValue = NSTextField(labelWithString: "")
    private let downloadButton = NSButton(title: L10n.downloadLatest, target: nil, action: nil)
    private let licenseButton = NSButton(title: L10n.obtainLicense, target: nil, action: nil)
    private let versionsButton = NSButton(title: L10n.versions, target: nil, action: nil)
    private let hintLabel = NSTextField(wrappingLabelWithString: L10n.encryptedHint)

    override func loadView() {
        view = NSView()
        empty.configure(symbol: "app.dashed", title: L10n.selectApp, subtitle: "")

        iconView.layer?.cornerRadius = 14
        nameLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        nameLabel.maximumNumberOfLines = 3
        bundleLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        bundleLabel.textColor = .secondaryLabelColor
        bundleLabel.lineBreakMode = .byTruncatingMiddle

        downloadButton.bezelStyle = .rounded
        downloadButton.target = self
        downloadButton.action = #selector(downloadClicked)
        licenseButton.bezelStyle = .rounded
        licenseButton.target = self
        licenseButton.action = #selector(licenseClicked)
        versionsButton.bezelStyle = .rounded
        versionsButton.target = self
        versionsButton.action = #selector(versionsClicked)

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.maximumNumberOfLines = 4

        let meta = NSStackView(views: [
            metaRow(L10n.appID, idValue),
            metaRow(L10n.version, versionValue),
            metaRow(L10n.price, priceValue),
            metaRow(L10n.platform, platformValue)
        ])
        meta.orientation = .vertical
        meta.alignment = .leading
        meta.spacing = 8

        let actions = NSStackView(views: [downloadButton, licenseButton, versionsButton])
        actions.orientation = .vertical
        actions.spacing = 8
        actions.alignment = .leading

        let stack = NSStackView(views: [iconView, nameLabel, bundleLabel, meta, actions, hintLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(16, after: bundleLabel)
        stack.setCustomSpacing(16, after: meta)
        stack.setCustomSpacing(16, after: actions)

        content.addSubview(stack)
        view.addSubview(empty)
        view.addSubview(content)
        empty.snp.makeConstraints { $0.edges.equalToSuperview() }
        content.snp.makeConstraints { $0.edges.equalToSuperview() }
        stack.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(18)
        }
        iconView.snp.makeConstraints { $0.size.equalTo(64) }
        [nameLabel, bundleLabel, meta, hintLabel, downloadButton, licenseButton, versionsButton, actions].forEach {
            $0.snp.makeConstraints { make in
                make.width.equalTo(stack)
            }
        }
        show(nil)
    }

    func show(_ app: StoreApp?) {
        self.app = app
        let hasApp = app != nil
        content.isHidden = !hasApp
        empty.isHidden = hasApp
        guard let app else { return }
        appID = app.id
        nameLabel.stringValue = app.displayName
        bundleLabel.stringValue = app.bundleID
        idValue.stringValue = app.id == 0 ? "—" : String(app.id)
        versionValue.stringValue = app.version.isEmpty ? "—" : app.version
        priceValue.stringValue = Formatters.price(app.price)
        platformValue.stringValue = app.platform?.title ?? "—"
        licenseButton.isHidden = !app.isFree
        hintLabel.stringValue = app.isFree ? "\(L10n.encryptedHint)\n\(L10n.purchaseIfNeededHint)" : L10n.encryptedHint
        iconView.image = ArtworkStore.shared.placeholder(named: app.displayName, size: 64)
        Task { [weak self] in
            let image = await ArtworkStore.shared.image(for: app.id, bundleID: app.bundleID)
            guard let self, self.appID == app.id, let image else { return }
            self.iconView.image = image
        }
    }

    @objc private func downloadClicked() {
        if let app { onDownload?(app) }
    }

    @objc private func licenseClicked() {
        if let app { onLicense?(app) }
    }

    @objc private func versionsClicked() {
        if let app { onVersions?(app) }
    }

    private func metaRow(_ title: String, _ value: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        value.font = .systemFont(ofSize: 12, weight: .medium)
        value.lineBreakMode = .byTruncatingMiddle
        let row = NSStackView(views: [label, value])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        label.snp.makeConstraints { $0.width.equalTo(72) }
        return row
    }
}
