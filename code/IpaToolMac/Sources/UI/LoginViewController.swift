import AppKit
import SnapKit

final class LoginViewController: NSViewController, NSTextFieldDelegate {
    var onSuccess: (() -> Void)?

    private let emailField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let authField = NSTextField()
    private let authLabel = NSTextField(labelWithString: L10n.authCode)
    private let hintLabel = NSTextField(wrappingLabelWithString: L10n.firstLoginHint)
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let signInButton = NSButton(title: L10n.signIn, target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private var authVisible = false {
        didSet { setAuthVisible(authVisible) }
    }

    override func loadView() {
        view = NSView()

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 13
        icon.layer?.masksToBounds = true
        icon.layer?.cornerCurve = .continuous

        let title = NSTextField(labelWithString: L10n.loginTitle)
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.alignment = .center

        let subtitle = NSTextField(wrappingLabelWithString: L10n.loginSubtitle)
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 3

        configureField(emailField, placeholder: "name@example.com")
        configureField(passwordField, placeholder: L10n.password)
        configureField(authField, placeholder: "000000")
        emailField.delegate = self
        passwordField.delegate = self
        authField.delegate = self

        let emailLabel = formLabel(L10n.appleID)
        let passwordLabel = formLabel(L10n.password)
        authLabel.font = .systemFont(ofSize: 12, weight: .medium)
        authLabel.textColor = .secondaryLabelColor

        signInButton.bezelStyle = .rounded
        signInButton.setButtonType(.momentaryPushIn)
        signInButton.target = self
        signInButton.action = #selector(signInClicked)
        signInButton.keyEquivalent = "\r"

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .center

        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.alignment = .center
        errorLabel.isHidden = true

        let buttonRow = NSStackView(views: [signInButton, spinner])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let form = NSStackView(views: [
            icon, title, subtitle,
            emailLabel, emailField,
            passwordLabel, passwordField,
            authLabel, authField,
            errorLabel,
            buttonRow,
            hintLabel
        ])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 8
        form.setCustomSpacing(16, after: subtitle)
        form.setCustomSpacing(4, after: emailLabel)
        form.setCustomSpacing(12, after: emailField)
        form.setCustomSpacing(4, after: passwordLabel)
        form.setCustomSpacing(12, after: passwordField)
        form.setCustomSpacing(4, after: authLabel)
        form.setCustomSpacing(16, after: authField)
        form.setCustomSpacing(12, after: buttonRow)

        view.addSubview(form)
        icon.snp.makeConstraints { make in
            make.size.equalTo(56)
            make.centerX.equalTo(form)
        }
        [title, subtitle, emailField, passwordField, authField, errorLabel, hintLabel, buttonRow, signInButton].forEach { item in
            item.snp.makeConstraints { make in
                make.width.equalTo(form)
            }
        }
        emailField.snp.makeConstraints { $0.height.equalTo(28) }
        passwordField.snp.makeConstraints { $0.height.equalTo(28) }
        authField.snp.makeConstraints { $0.height.equalTo(28) }
        signInButton.snp.makeConstraints { $0.height.equalTo(28) }
        form.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(-12)
            make.width.equalTo(320)
            make.top.greaterThanOrEqualToSuperview().offset(24)
            make.bottom.lessThanOrEqualToSuperview().offset(-24)
        }

        setAuthVisible(false)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.defaultButtonCell = signInButton.cell as? NSButtonCell
        view.window?.makeFirstResponder(emailField)
    }

    func focusEmail() {
        view.window?.makeFirstResponder(emailField)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            signInClicked()
            return true
        }
        return false
    }

    @objc private func signInClicked() {
        let email = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.stringValue
        let code = authField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            showError("请输入 Apple ID")
            view.window?.makeFirstResponder(emailField)
            return
        }
        guard !password.isEmpty else {
            showError("请输入密码")
            view.window?.makeFirstResponder(passwordField)
            return
        }
        setBusy(true)
        showError(nil)
        Task {
            do {
                try await Session.shared.login(
                    email: email,
                    password: password,
                    authCode: authVisible ? code : nil
                )
                setBusy(false)
                authVisible = false
                onSuccess?()
            } catch IPAToolError.authCodeRequired {
                setBusy(false)
                authVisible = true
                showError(L10n.authCodeHint)
                view.window?.makeFirstResponder(authField)
            } catch {
                setBusy(false)
                showError(error.localizedDescription)
            }
        }
    }

    private func configureField(_ field: NSTextField, placeholder: String) {
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
    }

    private func formLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func setAuthVisible(_ visible: Bool) {
        authLabel.isHidden = !visible
        authField.isHidden = !visible
    }

    private func setBusy(_ busy: Bool) {
        signInButton.isEnabled = !busy
        emailField.isEnabled = !busy
        passwordField.isEnabled = !busy
        authField.isEnabled = !busy
        if busy {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }

    private func showError(_ message: String?) {
        errorLabel.stringValue = message ?? ""
        errorLabel.isHidden = message == nil || message?.isEmpty == true
    }
}
