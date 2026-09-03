import AppKit
import Foundation

extension Notification.Name {
    static let sessionAccountDidChange = Notification.Name("sessionAccountDidChange")
    static let sessionSectionDidChange = Notification.Name("sessionSectionDidChange")
    static let sessionDownloadsDidChange = Notification.Name("sessionDownloadsDidChange")
    static let sessionStatusDidChange = Notification.Name("sessionStatusDidChange")
    static let sessionFolderDidChange = Notification.Name("sessionFolderDidChange")
}

@MainActor
final class Session {
    static let shared = Session()

    let service = IPAToolService()

    private(set) var account: AccountInfo?
    private(set) var section: SidebarSection = .search
    private(set) var downloads: [DownloadJob] = []
    private(set) var statusText = L10n.ready
    private(set) var statusIsError = false
    private(set) var isBusy = false

    var isLoggedIn: Bool { account != nil }

    private var downloadRunning = false
    private let folderKey = "downloadFolderPath"
    private let store = DownloadStore.shared

    private init() {
        downloads = store.loadAll()
        ArtworkStore.shared.countryCode = StoreFront.countryCode(from: StoreFront.accountStoreFront())
    }

    var downloadFolder: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: folderKey), !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("IPA Tool")
        }
        set {
            UserDefaults.standard.set(newValue.path, forKey: folderKey)
            NotificationCenter.default.post(name: .sessionFolderDidChange, object: self)
        }
    }

    func refreshAccount() async {
        do {
            account = try await service.accountInfo()
            ArtworkStore.shared.countryCode = account?.countryCode
            setStatus("\(L10n.signedIn) \(account?.name ?? "")", error: false, busy: false)
        } catch {
            account = nil
            ArtworkStore.shared.countryCode = nil
            setStatus(L10n.notSignedIn, error: false, busy: false)
        }
        NotificationCenter.default.post(name: .sessionAccountDidChange, object: self)
    }

    func login(email: String, password: String, authCode: String?) async throws {
        setStatus(L10n.signingIn, error: false, busy: true)
        do {
            account = try await service.login(email: email, password: password, authCode: authCode)
            ArtworkStore.shared.countryCode = account?.countryCode
            setStatus("\(L10n.signedIn) \(account?.name ?? "")", error: false, busy: false)
            NotificationCenter.default.post(name: .sessionAccountDidChange, object: self)
        } catch {
            setStatus(error.localizedDescription, error: true, busy: false)
            throw error
        }
    }

    func signOut() async {
        setStatus("正在退出…", error: false, busy: true)
        do {
            try await service.revoke()
            account = nil
            ArtworkStore.shared.countryCode = nil
            setStatus(L10n.signedOut, error: false, busy: false)
        } catch {
            account = nil
            ArtworkStore.shared.countryCode = nil
            setStatus(error.localizedDescription, error: true, busy: false)
        }
        NotificationCenter.default.post(name: .sessionAccountDidChange, object: self)
    }

    func selectSection(_ section: SidebarSection) {
        guard self.section != section else { return }
        self.section = section
        NotificationCenter.default.post(name: .sessionSectionDidChange, object: self)
    }

    func enqueueDownload(app: StoreApp, versionID: String? = nil, purchaseIfNeeded: Bool? = nil) {
        let job = DownloadJob(
            id: UUID(),
            appName: app.name.isEmpty ? app.bundleID : app.name,
            bundleID: app.bundleID,
            appID: app.id,
            versionID: versionID,
            platform: app.platform,
            purchaseIfNeeded: purchaseIfNeeded ?? app.isFree,
            status: .queued,
            outputPath: nil,
            errorMessage: nil,
            createdAt: Date()
        )
        downloads.insert(job, at: 0)
        store.upsert(job)
        NotificationCenter.default.post(name: .sessionDownloadsDidChange, object: self)
        setStatus("已加入下载队列：\(job.appName)", error: false, busy: isBusy)
        pumpDownloads()
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func chooseDownloadFolder(from window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = downloadFolder
        panel.prompt = "选择"
        panel.message = "之后下载的 IPA 会保存到这个文件夹"
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            self.downloadFolder = url
            self.setStatus("下载目录：\(Formatters.homeRelative(url))", error: false, busy: false)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    func setStatus(_ text: String, error: Bool, busy: Bool) {
        statusText = text
        statusIsError = error
        isBusy = busy
        NotificationCenter.default.post(name: .sessionStatusDidChange, object: self)
    }

    private func pumpDownloads() {
        guard !downloadRunning else { return }
        guard let index = downloads.firstIndex(where: { $0.status == .queued }) else { return }
        downloadRunning = true
        downloads[index].status = .running
        store.upsert(downloads[index])
        let job = downloads[index]
        NotificationCenter.default.post(name: .sessionDownloadsDidChange, object: self)
        setStatus("\(L10n.downloading) \(job.appName)", error: false, busy: true)

        let app = StoreApp(
            id: job.appID,
            bundleID: job.bundleID,
            name: job.appName,
            version: "",
            price: job.purchaseIfNeeded ? 0 : 1,
            purchaseDate: nil,
            platform: job.platform
        )
        let folder = downloadFolder
        let versionID = job.versionID
        let purchase = job.purchaseIfNeeded

        Task {
            do {
                let result = try await self.service.download(
                    app: app,
                    outputDirectory: folder,
                    versionID: versionID,
                    purchaseIfNeeded: purchase
                )
                self.finish(jobID: job.id, path: URL(fileURLWithPath: result.outputPath), error: nil)
            } catch {
                self.finish(jobID: job.id, path: nil, error: error.localizedDescription)
            }
        }
    }

    private func finish(jobID: UUID, path: URL?, error: String?) {
        if let index = downloads.firstIndex(where: { $0.id == jobID }) {
            downloads[index].status = error == nil ? .succeeded : .failed
            downloads[index].outputPath = path
            downloads[index].errorMessage = error
            store.upsert(downloads[index])
        }
        downloadRunning = false
        NotificationCenter.default.post(name: .sessionDownloadsDidChange, object: self)
        if let error {
            setStatus(error, error: true, busy: false)
        } else if let path {
            setStatus("已保存到 \(Formatters.homeRelative(path))", error: false, busy: false)
        } else {
            setStatus(L10n.ready, error: false, busy: false)
        }
        pumpDownloads()
    }
}
