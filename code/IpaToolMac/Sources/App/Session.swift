import AppKit
import Darwin
import Foundation

extension Notification.Name {
    static let sessionAccountDidChange = Notification.Name("sessionAccountDidChange")
    static let sessionSectionDidChange = Notification.Name("sessionSectionDidChange")
    static let sessionDownloadsDidChange = Notification.Name("sessionDownloadsDidChange")
    static let sessionDownloadProgressDidChange = Notification.Name("sessionDownloadProgressDidChange")
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

    private var downloadTask: Task<Void, Never>?
    private var isTerminating = false
    private var lastProgressUpdate = Date.distantPast
    private let folderKey = "downloadFolderPath"
    private let store = DownloadStore.shared
    private var folderWatcher: DispatchSourceFileSystemObject?
    private var folderDescriptor: Int32 = -1
    private var pruneWork: DispatchWorkItem?

    private init() {
        downloads = store.loadAll()
        KeychainAccess.allowIpatoolWithoutPrompt()
        ArtworkStore.shared.countryCode = StoreFront.countryCode(from: StoreFront.accountStoreFront())
        startWatchingDownloadFolder()
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
            startWatchingDownloadFolder()
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
        if isLoggedIn { pumpDownloads() }
    }

    func login(email: String, password: String, authCode: String?) async throws {
        setStatus(L10n.signingIn, error: false, busy: true)
        KeychainAccess.noteCredentialsChanged()
        do {
            account = try await service.login(email: email, password: password, authCode: authCode)
            ArtworkStore.shared.countryCode = account?.countryCode
            setStatus("\(L10n.signedIn) \(account?.name ?? "")", error: false, busy: false)
            NotificationCenter.default.post(name: .sessionAccountDidChange, object: self)
            pumpDownloads()
        } catch {
            setStatus(error.localizedDescription, error: true, busy: false)
            throw error
        }
    }

    func signOut() async {
        setStatus(L10n.signingOut, error: false, busy: true)
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
        guard !downloads.contains(where: {
            ($0.status == .queued || $0.status == .running) && $0.isSameDownload(as: job)
        }) else {
            setStatus(L10n.downloadAlreadyQueued, error: false, busy: isBusy)
            return
        }
        downloads.insert(job, at: 0)
        store.upsert(job)
        NotificationCenter.default.post(name: .sessionDownloadsDidChange, object: self)
        setStatus(String(format: L10n.queuedFormat, job.appName), error: false, busy: isBusy)
        pumpDownloads()
    }

    func cancelDownload(_ id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }), downloads[index].canCancel else { return }
        if downloads[index].status == .running {
            downloads[index].isCancelling = true
            downloadTask?.cancel()
        } else {
            downloads[index].status = .cancelled
            store.upsert(downloads[index])
        }
        NotificationCenter.default.post(name: .sessionDownloadsDidChange, object: self)
    }

    func retryDownload(_ id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }), downloads[index].canRetry else { return }
        var job = downloads[index]
        guard !downloads.contains(where: {
            ($0.status == .queued || $0.status == .running) && $0.isSameDownload(as: job)
        }) else {
            setStatus(L10n.downloadAlreadyQueued, error: false, busy: isBusy)
            return
        }
        job.status = .queued
        job.errorMessage = nil
        job.progress = nil
        job.createdAt = Date()
        downloads.remove(at: index)
        downloads.insert(job, at: 0)
        store.upsert(job)
        NotificationCenter.default.post(name: .sessionDownloadsDidChange, object: self)
        pumpDownloads()
    }

    func prepareForTermination() async {
        isTerminating = true
        let task = downloadTask
        task?.cancel()
        await task?.value
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func deleteDownloads(_ ids: [UUID]) {
        var removedNames: [String] = []
        for id in ids {
            guard let index = downloads.firstIndex(where: { $0.id == id }) else { continue }
            let job = downloads[index]
            guard job.canDelete else { continue }
            if let url = job.outputPath, FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
            removedNames.append(job.appName)
            downloads.remove(at: index)
            store.delete(id)
        }
        guard !removedNames.isEmpty else { return }
        NotificationCenter.default.post(name: .sessionDownloadsDidChange, object: self)
        if removedNames.count == 1 {
            setStatus(String(format: L10n.deletedOne, removedNames[0]), error: false, busy: isBusy)
        } else {
            setStatus(String(format: L10n.deletedMany, removedNames.count), error: false, busy: isBusy)
        }
    }

    func pruneMissingDownloads() {
        let staleIDs = downloads.compactMap { job -> UUID? in
            job.status == .succeeded && !job.fileExists ? job.id : nil
        }
        guard !staleIDs.isEmpty else { return }
        for id in staleIDs {
            downloads.removeAll { $0.id == id }
            store.delete(id)
        }
        NotificationCenter.default.post(name: .sessionDownloadsDidChange, object: self)
    }

    func chooseDownloadFolder(from window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = downloadFolder
        panel.prompt = L10n.choose
        panel.message = L10n.chooseFolderMessage
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            self.downloadFolder = url
            self.setStatus(String(format: L10n.folderSet, Formatters.homeRelative(url)), error: false, busy: false)
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
        guard downloadTask == nil, isLoggedIn, !isTerminating else { return }
        guard let index = downloads.lastIndex(where: { $0.status == .queued }) else { return }
        downloads[index].status = .running
        lastProgressUpdate = .distantPast
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

        downloadTask = Task {
            do {
                let result = try await self.service.download(
                    app: app,
                    outputDirectory: folder,
                    versionID: versionID,
                    purchaseIfNeeded: purchase,
                    onProgress: { [weak self] progress in
                        Task { @MainActor in self?.updateProgress(jobID: job.id, progress: progress) }
                    }
                )
                self.finish(jobID: job.id, path: URL(fileURLWithPath: result.outputPath), error: nil)
            } catch is CancellationError {
                self.finish(jobID: job.id, path: nil, error: nil, cancelled: true)
            } catch {
                self.finish(jobID: job.id, path: nil, error: error.localizedDescription)
            }
        }
    }

    private func updateProgress(jobID: UUID, progress: DownloadProgress) {
        guard let index = downloads.firstIndex(where: { $0.id == jobID }),
              downloads[index].status == .running, !downloads[index].isCancelling else { return }
        guard Date().timeIntervalSince(lastProgressUpdate) >= 0.15 || progress.percent == 100 else { return }
        downloads[index].progress = progress
        lastProgressUpdate = Date()
        NotificationCenter.default.post(name: .sessionDownloadProgressDidChange, object: self, userInfo: ["jobID": jobID])
    }

    private func finish(jobID: UUID, path: URL?, error: String?, cancelled: Bool = false) {
        if let index = downloads.firstIndex(where: { $0.id == jobID }) {
            downloads[index].status = cancelled ? .cancelled : (error == nil ? .succeeded : .failed)
            downloads[index].outputPath = path
            downloads[index].errorMessage = error
            downloads[index].progress = nil
            downloads[index].isCancelling = false
            store.upsert(downloads[index])
        }
        downloadTask = nil
        NotificationCenter.default.post(name: .sessionDownloadsDidChange, object: self)
        if cancelled {
            setStatus(L10n.cancelled, error: false, busy: false)
        } else if let error {
            setStatus(error, error: true, busy: false)
        } else if let path {
            setStatus(String(format: L10n.savedTo, Formatters.homeRelative(path)), error: false, busy: false)
        } else {
            setStatus(L10n.ready, error: false, busy: false)
        }
        pumpDownloads()
    }

    private func startWatchingDownloadFolder() {
        stopWatchingDownloadFolder()
        let folder = downloadFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        folderDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.schedulePrune()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        folderWatcher = source
    }

    private func stopWatchingDownloadFolder() {
        folderWatcher?.cancel()
        folderWatcher = nil
        folderDescriptor = -1
        pruneWork?.cancel()
        pruneWork = nil
    }

    private func schedulePrune() {
        pruneWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pruneMissingDownloads()
        }
        pruneWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
}
