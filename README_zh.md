# IPA Tool for Mac

[English](README.md)

这是 [ipatool](https://github.com/majd/ipatool) 的 macOS 图形界面。用窗口搜索 App Store、查看已购应用、下载 IPA，不用再敲命令行。

本应用是 GUI 外壳，真正和 App Store 通信的仍是 `ipatool` 命令行。先装好 `ipatool`，再打开这个 App 即可使用。

## 环境要求

- macOS 13 或更高
- Xcode 15 或更高（用于编译本应用）
- [Homebrew](https://brew.sh)
- [ipatool](https://github.com/majd/ipatool)

## 安装

### 1. 安装 ipatool

```bash
brew install ipatool
```

图形界面会在下面两个路径查找 `ipatool`：

- `/opt/homebrew/bin/ipatool`（Apple Silicon）
- `/usr/local/bin/ipatool`（Intel）

### 2. 编译并运行本应用

```bash
git clone https://github.com/pzee/ipatoolForMac.git
cd ipatoolForMac/code
open IpaToolMac.xcodeproj
```

在 Xcode 里选中 **IpaToolMac** scheme，按 **⌘R** 运行。

也可以用命令行编译：

```bash
cd code
make build
```

这条路径需要先安装 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`。

编译成功后，应用名称是 **IPA Tool**。需要的话可以拷到 `/Applications`。

### 3. 去掉隔离属性

应用没有经过 Apple 公证，第一次打开可能被系统拦截。在终端执行：

```bash
xattr -rd com.apple.quarantine /Applications/IPA\ Tool.app/
```

然后再从「应用程序」里打开 **IPA Tool**。

## 使用方法

1. 打开 **IPA Tool**。
2. 用能访问 App Store 的 Apple ID 登录。如果开了双重认证，按提示输入 6 位验证码。首次登录可能要等几分钟。
3. 用左侧栏切换功能：
   - **搜索** — 搜索 App Store。可用 iPhone / iPad / Apple TV / visionOS 切换平台。
   - **已购** — 查看这个 Apple ID 已经拥有的应用。
   - **下载** — 下载队列和已保存的文件。
4. 选中一个应用后可以：
   - **下载最新版** — 下载当前版本。
   - **获取授权** — 免费应用在需要时获取授权。
   - **历史版本** — 列出历史版本并下载其中某一个。
5. IPA 默认保存在 `~/Downloads/IPA Tool`。可在工具栏、下载页，或 **账户 → 选择下载目录…**（⌘O）里更改。

下载下来的 IPA 仍是 FairPlay 加密包，需要用同一个已购账号的设备安装。

### 快捷键

| 快捷键 | 作用 |
| --- | --- |
| ⌘L | 聚焦登录 |
| ⌘1 / ⌘2 / ⌘3 | 搜索 / 已购 / 下载 |
| ⌘O | 选择下载目录 |
| ⌘R | 刷新 |
| ⌘Q | 退出 |

## 和 ipatool 的关系

IPA Tool for Mac 没有自己实现 App Store 协议。界面操作会调用 `ipatool`，并加上 `--format json --non-interactive`，再把结果画到窗口里：

| 界面操作 | 对应的 ipatool 命令 |
| --- | --- |
| 登录 | `ipatool auth login` |
| 账户信息 | `ipatool auth info` |
| 退出登录 | `ipatool auth revoke` |
| 搜索 | `ipatool search` |
| 已购列表 | `ipatool list-purchases` |
| 获取授权 | `ipatool purchase` |
| 历史版本 | `ipatool list-versions` / `get-version-metadata` |
| 下载 | `ipatool download` |

登录凭证仍存在 `ipatool` 自己的钥匙串项（`ipatool-auth.service`）里，和命令行是同一套。

## 说明

- 请使用已经能正常访问 App Store 的 Apple ID。
- 免费应用在下载时，如有需要会自动获取授权。
- 本项目与 Apple 无关。
- 请遵守 Apple 服务条款，仅供个人使用。

## 致谢

应用 Logo 由 [ip-as-logo-skill](https://github.com/s1dashu/ip-as-logo-skill) 生成。

## 许可证

MIT，见 [LICENSE](LICENSE)。

`ipatool` 同样是 MIT 许可：[majd/ipatool](https://github.com/majd/ipatool)。
