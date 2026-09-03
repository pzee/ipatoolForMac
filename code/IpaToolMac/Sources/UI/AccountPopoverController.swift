import AppKit
import SnapKit

final class AccountPopoverController: NSViewController {
    private let nameLabel = NSTextField(labelWithString: L10n.notSignedIn)
    private let mailLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let changeButton = NSButton(title: "更改下载目录…", target: nil, action: nil)
    private let signOutButton = NSButton(title: L10n.signOut, target: nil, action: nil)

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 168))
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        mailLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        mailLabel.textColor = .secondaryLabelColor
        mailLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        changeButton.title = L10n.chooseDownloadFolder
        changeButton.bezelStyle = .rounded
        signOutButton.bezelStyle = .rounded
        changeButton.target = self
        signOutButton.target = self
        changeButton.action = #selector(changeFolder)
        signOutButton.action = #selector(signOut)

        let folderCaption = NSTextField(labelWithString: L10n.downloadFolder)
        folderCaption.font = .systemFont(ofSize: 11)
        folderCaption.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [nameLabel, mailLabel, folderCaption, pathLabel, changeButton, signOutButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: mailLabel)
        stack.setCustomSpacing(10, after: pathLabel)
        view.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(12)
        }
        [changeButton, signOutButton].forEach {
            $0.snp.makeConstraints { make in
                make.width.equalTo(stack)
            }
        }
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .sessionAccountDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .sessionFolderDidChange, object: nil)
    }

    @objc func refresh() {
        if let account = Session.shared.account {
            nameLabel.stringValue = account.name
            mailLabel.stringValue = account.email
            signOutButton.isHidden = false
        } else {
            nameLabel.stringValue = L10n.notSignedIn
            mailLabel.stringValue = "登录后显示 Apple ID"
            signOutButton.isHidden = true
        }
        pathLabel.stringValue = Formatters.homeRelative(Session.shared.downloadFolder)
    }

    @objc private func changeFolder() {
        let parent = view.window?.sheetParent ?? NSApp.keyWindow ?? view.window
        Session.shared.chooseDownloadFolder(from: parent)
    }

    @objc private func signOut() {
        Task { await Session.shared.signOut() }
    }
}
