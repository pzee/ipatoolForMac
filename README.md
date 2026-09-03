# IPA Tool for Mac

[中文](README_zh.md)

A native macOS GUI for [ipatool](https://github.com/majd/ipatool). Search the App Store, browse purchases, and download IPA packages without using the command line.

This app is a graphical front end. All App Store requests still go through the official `ipatool` CLI.

## Requirements

- macOS 13 or later
- Xcode 15 or later (to build the app)
- [Homebrew](https://brew.sh)
- [ipatool](https://github.com/majd/ipatool)

## Install

### 1. Install ipatool

```bash
brew install ipatool
```

The GUI looks for `ipatool` at:

- `/opt/homebrew/bin/ipatool` (Apple Silicon)
- `/usr/local/bin/ipatool` (Intel)

### 2. Build and run the app

```bash
git clone https://github.com/pzee/ipatoolForMac.git
cd ipatoolForMac/code
open IpaToolMac.xcodeproj
```

In Xcode, select the **IpaToolMac** scheme and press **⌘R**.

If you prefer the command line:

```bash
cd code
make build
```

That needs [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

After a successful build, the app is named **IPA Tool**. Copy it to `/Applications` if you want.

### 3. Remove Gatekeeper quarantine

The app is not notarized. macOS may block it the first time you open it. Run:

```bash
xattr -rd com.apple.quarantine /Applications/IPA\ Tool.app/
```

Then open **IPA Tool** from Applications.

## Usage

1. Launch **IPA Tool**.
2. Sign in with an Apple ID that can access the App Store. If two-factor authentication is on, enter the 6-digit code when prompted. The first login may take a few minutes.
3. Use the sidebar:
   - **Search** — search the App Store. Switch platform with iPhone / iPad / Apple TV / visionOS.
   - **Purchases** — apps already owned by this Apple ID.
   - **Downloads** — download queue and saved files.
4. Select an app, then:
   - **Download Latest** — download the current version.
   - **Obtain License** — get a license for a free app if needed.
   - **Versions** — list historical versions and download one of them.
5. Files are saved to `~/Downloads/IPA Tool` by default. Change the folder from the toolbar, the Downloads page, or **Account → Choose Download Folder…** (⌘O).

Downloaded IPAs are still FairPlay-encrypted. Install them on a device signed in with the same Apple ID.

### Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘L | Focus sign in |
| ⌘1 / ⌘2 / ⌘3 | Search / Purchases / Downloads |
| ⌘O | Choose download folder |
| ⌘R | Refresh |
| ⌘Q | Quit |

## How it relates to ipatool

IPA Tool for Mac does not reimplement the App Store protocol. It runs `ipatool` with `--format json --non-interactive` and maps the results into the UI:

| UI action | ipatool command |
| --- | --- |
| Sign in | `ipatool auth login` |
| Account info | `ipatool auth info` |
| Sign out | `ipatool auth revoke` |
| Search | `ipatool search` |
| Purchases | `ipatool list-purchases` |
| Obtain license | `ipatool purchase` |
| Versions | `ipatool list-versions` / `get-version-metadata` |
| Download | `ipatool download` |

Credentials stay in the `ipatool` keychain item (`ipatool-auth.service`), same as the CLI.

## Notes

- Use an Apple ID that already works with the App Store.
- Free apps can obtain a license automatically when you download.
- This project is not affiliated with Apple.
- Follow Apple’s terms of service. For personal use only.

## Credits

The app logo was generated with [ip-as-logo-skill](https://github.com/s1dashu/ip-as-logo-skill).

## License

MIT. See [LICENSE](LICENSE).

`ipatool` is also MIT-licensed: [majd/ipatool](https://github.com/majd/ipatool).
