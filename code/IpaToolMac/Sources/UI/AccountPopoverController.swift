import AppKit
import SnapKit

final class AccountPopoverController: NSViewController {
    private let nameLabel = NSTextField(labelWithString: L10n.notSignedIn)
    private let mailLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let changeButton = NSButton(title: L10n.chooseDownloadFolder, target: nil, action: nil)
    private let signOutButton = NSButton(title: L10n.signOut, target: nil, action: nil)
    private let languagePopup = NSPopUpButton()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 236))
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

        let languageCaption = NSTextField(labelWithString: L10n.language)
        languageCaption.font = .systemFont(ofSize: 11)
        languageCaption.textColor = .secondaryLabelColor
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        reloadLanguagePopup()

        let stack = NSStackView(views: [
            nameLabel, mailLabel,
            folderCaption, pathLabel, changeButton,
            languageCaption, languagePopup,
            signOutButton
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: mailLabel)
        stack.setCustomSpacing(10, after: pathLabel)
        stack.setCustomSpacing(10, after: changeButton)
        stack.setCustomSpacing(10, after: languagePopup)
        view.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(12)
        }
        [changeButton, signOutButton, languagePopup].forEach {
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
            mailLabel.stringValue = L10n.signInToShowAccount
            signOutButton.isHidden = true
        }
        pathLabel.stringValue = Formatters.homeRelative(Session.shared.downloadFolder)
        reloadLanguagePopup()
    }

    private func reloadLanguagePopup() {
        languagePopup.target = nil
        languagePopup.removeAllItems()
        AppLanguage.allCases.forEach { languagePopup.addItem(withTitle: $0.title) }
        if let index = AppLanguage.allCases.firstIndex(of: .current) {
            languagePopup.selectItem(at: index)
        }
        languagePopup.target = self
    }

    @objc private func languageChanged() {
        let index = languagePopup.indexOfSelectedItem
        guard AppLanguage.allCases.indices.contains(index) else { return }
        AppLanguage.select(AppLanguage.allCases[index])
    }

    @objc private func changeFolder() {
        let parent = view.window?.sheetParent ?? NSApp.keyWindow ?? view.window
        Session.shared.chooseDownloadFolder(from: parent)
    }

    @objc private func signOut() {
        Task { await Session.shared.signOut() }
    }
}
