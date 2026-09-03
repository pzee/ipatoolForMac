import AppKit
import SnapKit

final class SidebarViewController: NSViewController {
    var onSelect: ((SidebarSection) -> Void)?
    var onSignOut: (() -> Void)?

    private let rows: [SidebarRow] = SidebarSection.allCases.map {
        SidebarRow(title: $0.title, symbol: $0.symbolName, tag: $0.rawValue)
    }
    private let nameLabel = NSTextField(labelWithString: L10n.notSignedIn)
    private let emailLabel = NSTextField(labelWithString: "")
    private let signOutButton = NSButton(title: L10n.signOut, target: nil, action: nil)

    override func loadView() {
        view = NSView()

        let itemStack = NSStackView(views: rows)
        itemStack.orientation = .vertical
        itemStack.spacing = 2
        itemStack.alignment = .leading
        rows.forEach { row in
            row.target = self
            row.action = #selector(rowClicked(_:))
            row.snp.makeConstraints { $0.width.equalTo(itemStack.snp.width) }
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.setContentCompressionResistancePriority(.init(1), for: .vertical)

        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        emailLabel.font = .systemFont(ofSize: 11)
        emailLabel.textColor = .secondaryLabelColor
        emailLabel.lineBreakMode = .byTruncatingTail

        signOutButton.bezelStyle = .roundRect
        signOutButton.controlSize = .small
        signOutButton.font = .systemFont(ofSize: 11)
        signOutButton.target = self
        signOutButton.action = #selector(signOutClicked)

        let footer = NSStackView(views: [nameLabel, emailLabel, signOutButton])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 4

        let stack = NSStackView(views: [itemStack, spacer, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        view.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(NSEdgeInsets(top: 10, left: 10, bottom: 12, right: 10))
        }
        itemStack.snp.makeConstraints { $0.width.equalTo(stack.snp.width) }
        footer.snp.makeConstraints { $0.width.equalTo(stack.snp.width) }

        select(.search)
        applyAccount(nil)
    }

    func select(_ section: SidebarSection) {
        rows.forEach { $0.isActive = $0.tag == section.rawValue }
    }

    func applyAccount(_ account: AccountInfo?) {
        if let account {
            nameLabel.stringValue = account.name
            emailLabel.stringValue = account.email
            emailLabel.isHidden = false
            signOutButton.isHidden = false
        } else {
            nameLabel.stringValue = L10n.notSignedIn
            emailLabel.stringValue = ""
            emailLabel.isHidden = true
            signOutButton.isHidden = true
        }
    }

    @objc private func rowClicked(_ sender: SidebarRow) {
        guard let section = SidebarSection(rawValue: sender.tag) else { return }
        select(section)
        onSelect?(section)
    }

    @objc private func signOutClicked() {
        onSignOut?()
    }
}

final class SidebarRow: NSButton {
    var isActive = false {
        didSet { applyAppearance() }
    }

    convenience init(title: String, symbol: String, tag: Int) {
        self.init(title: title, target: nil, action: nil)
        self.tag = tag
        bezelStyle = .shadowlessSquare
        isBordered = false
        image = Symbol.image(symbol, size: 13, weight: .medium)
        imagePosition = .imageLeading
        alignment = .left
        imageHugsTitle = true
        font = .systemFont(ofSize: 13, weight: .medium)
        focusRingType = .none
        contentTintColor = .labelColor
        wantsLayer = true
        layer?.cornerRadius = 6
        applyAppearance()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 32)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private func applyAppearance() {
        if isActive {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            contentTintColor = .controlAccentColor
            font = .systemFont(ofSize: 13, weight: .semibold)
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            contentTintColor = .labelColor
            font = .systemFont(ofSize: 13, weight: .medium)
        }
    }
}
