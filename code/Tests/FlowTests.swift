import XCTest
import AppKit

final class FlowTests: XCTestCase {
    @MainActor
    func testProgressRowLayoutAndCancellationStates() {
        let cell = DownloadTableCellView(frame: NSRect(x: 0, y: 0, width: 700, height: 64))
        var job = DownloadJob(id: UUID(), appName: "Progress preview", bundleID: "com.example.test", appID: 0,
                              versionID: nil, platform: .iphone, purchaseIfNeeded: false,
                              status: .running, outputPath: nil, errorMessage: nil, createdAt: Date(),
                              progress: DownloadProgress(percent: 42, detail: "42/100 MB, 8 MB/s"))
        cell.updateStatus(job)
        cell.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }
        let views = descendants(cell)
        let bar = views.compactMap { $0 as? NSProgressIndicator }.first!
        let button = views.compactMap { $0 as? NSButton }.first!
        XCTAssertFalse(bar.isHidden)
        XCTAssertFalse(bar.isIndeterminate)
        XCTAssertEqual(bar.doubleValue, 42)
        XCTAssertGreaterThan(bar.frame.width, 100)
        XCTAssertTrue(cell.bounds.contains(bar.convert(bar.bounds, to: cell)))
        XCTAssertTrue(button.isEnabled)
        job.isCancelling = true
        cell.updateStatus(job)
        XCTAssertFalse(button.isEnabled)
        job.isCancelling = false
        job.status = .cancelled
        cell.updateStatus(job)
        XCTAssertTrue(bar.isHidden)
        XCTAssertTrue(button.isEnabled)
        XCTAssertEqual(button.title, L10n.retry)
        job.status = .succeeded
        cell.updateStatus(job)
        cell.layoutSubtreeIfNeeded()
        let pill = views.compactMap { $0 as? StatusPillView }.first!
        XCTAssertEqual(pill.convert(pill.bounds, to: cell).maxX, cell.bounds.maxX - 20, accuracy: 1)
    }

    func testDownloadNamesUseAppNameAndPreserveExistingFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var app = StoreApp(id: 42, bundleID: "com.example.app", name: "红果短剧", version: "1.0", price: 0, platform: .iphone)
        let first = IPAToolService.downloadDestination(app: app, fileExtension: "ipa", directory: folder)
        XCTAssertEqual(first.lastPathComponent, "红果短剧.ipa")
        try Data("existing file".utf8).write(to: first)
        let second = IPAToolService.downloadDestination(app: app, fileExtension: "ipa", directory: folder)
        XCTAssertEqual(second.lastPathComponent, "红果短剧 (2).ipa")
        try Data().write(to: second)
        XCTAssertEqual(IPAToolService.downloadDestination(app: app, fileExtension: "ipa", directory: folder).lastPathComponent, "红果短剧 (3).ipa")
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "existing file")
        app.name = "../ App / Pro:\nTest \\ "
        let safe = IPAToolService.downloadDestination(app: app, fileExtension: "ipa", directory: folder)
        XCTAssertEqual(safe.lastPathComponent, "App Pro Test.ipa")
        XCTAssertEqual(safe.deletingLastPathComponent().path, folder.path)
        app.name = String(repeating: "应用🚀", count: 100)
        let long = IPAToolService.downloadDestination(app: app, fileExtension: "ipa", directory: folder)
        XCTAssertLessThan(long.lastPathComponent.utf8.count, 255)
        try Data().write(to: long)
        app.name = "../:"
        XCTAssertEqual(IPAToolService.downloadDestination(app: app, fileExtension: "ipa", directory: folder).lastPathComponent, "App 42.ipa")
    }

    func testPaginationCommitsOnlyAfterSuccessAndBlocksDuplicateRequests() {
        var pager = PurchasePagination()
        XCTAssertFalse(pager.canGoBack)
        XCTAssertFalse(pager.canGoForward)
        XCTAssertTrue(pager.begin(1))
        XCTAssertFalse(pager.begin(2))
        pager.finish(PurchasePage(apps: [], count: 20, totalCount: 41, page: 1))
        XCTAssertTrue(pager.canGoForward)
        XCTAssertTrue(pager.begin(2))
        XCTAssertFalse(pager.canGoForward)
        pager.fail()
        XCTAssertEqual(pager.page, 1)
        XCTAssertTrue(pager.canGoForward)
        XCTAssertTrue(pager.begin(2))
        pager.finish(PurchasePage(apps: [], count: 20, totalCount: 41, page: 2))
        XCTAssertTrue(pager.canGoBack)
        XCTAssertTrue(pager.canGoForward)
        XCTAssertTrue(pager.begin(3))
        pager.finish(PurchasePage(apps: [], count: 1, totalCount: 41, page: 3))
        XCTAssertFalse(pager.canGoForward)
        pager = PurchasePagination()
        XCTAssertTrue(pager.begin(1))
        pager.finish(PurchasePage(apps: [], count: 0, totalCount: 0, page: 1))
        XCTAssertFalse(pager.canGoForward)
        XCTAssertFalse(pager.begin(0))
    }

    func testProgressParsingAndSplitUTF8KeepFinalJSON() {
        var buffer = CLIOutputBuffer()
        var progress: [DownloadProgress] = []
        let output = "\rdownloading  42% |████    | (42/100 MB, 8 MB/s)\r       \r{\"success\":true,\"output\":\"/下载/应用.ipa\"}"
        for byte in output.utf8 {
            buffer.append(Data([byte])) { progress.append($0) }
        }
        buffer.finish { progress.append($0) }
        XCTAssertEqual(progress.last, DownloadProgress(percent: 42, detail: "42/100 MB, 8 MB/s"))
        XCTAssertFalse(buffer.text.contains("downloading"))
        XCTAssertEqual(CLIEnvelope.parseLines(buffer.text).last?.output, "/下载/应用.ipa")
        XCTAssertEqual(DownloadProgress.parse("\u{001B}[2Kdownloading 100% |████| (100/100 MB)")?.percent, 100)
        XCTAssertNil(DownloadProgress.parse("downloading 101%"))
        XCTAssertNil(DownloadProgress.parse("downloading -2%"))
        XCTAssertNil(DownloadProgress.parse("{\"error\":\"downloading 42%\"}"))
        XCTAssertNil(DownloadProgress.parse("unrelated 25%"))
    }

    func testDrainsBothPipesBeyondTheirCapacity() async throws {
        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "i=0; while [ $i -lt 12000 ]; do printf 'stdout record\\n'; printf 'stderr record\\n' >&2; i=$((i+1)); done"]
        )
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.split(separator: "\n").count, 12000)
        XCTAssertEqual(result.stderr.split(separator: "\n").count, 12000)
    }

    func testProgressArrivesBeforeProcessExits() async throws {
        let update = expectation(description: "live progress")
        update.assertForOverFulfill = false
        let task = Task {
            try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf '\\rdownloading  25%% |██| (25/100 MB)'; sleep 2; printf '\\r{\"success\":true,\"output\":\"/tmp/app.ipa\"}'"],
                onProgress: { progress in
                    if progress.percent == 25 { update.fulfill() }
                }
            )
        }
        await fulfillment(of: [update], timeout: 1)
        let result = try await task.value
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(CLIEnvelope.parseLines(result.stdout).last?.output, "/tmp/app.ipa")
    }

    func testCancellationTerminatesProcessAndAllowsNextCommand() async throws {
        let ready = expectation(description: "process started")
        ready.assertForOverFulfill = false
        let task = Task {
            try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf '\\rdownloading  1%% | | (1/100 MB)'; exec /bin/sleep 30"],
                onProgress: { _ in ready.fulfill() }
            )
        }
        await fulfillment(of: [ready], timeout: 2)
        let start = Date()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertLessThan(Date().timeIntervalSince(start), 4)
        }
        let result = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
        XCTAssertEqual(result.status, 0)
    }

    func testFailureAndLaunchErrorReturnWithoutHanging() async throws {
        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf '{\"success\":false,\"error\":\"network unavailable\"}' >&2; exit 7"]
        )
        XCTAssertEqual(result.status, 7)
        XCTAssertEqual(CLIEnvelope.parseLines(result.stderr).last?.errorMessage, "network unavailable")
        do {
            _ = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/does/not/exist/ipatool"), arguments: [])
            XCTFail("Expected launch error")
        } catch { }
    }

    func testDownloadIdentityAndActions() {
        let first = DownloadJob(id: UUID(), appName: "App", bundleID: "com.example.app", appID: 42,
                                versionID: nil, platform: .iphone, purchaseIfNeeded: false,
                                status: .queued, outputPath: nil, errorMessage: nil, createdAt: Date())
        var second = first
        XCTAssertTrue(first.isSameDownload(as: second))
        second.versionID = "123"
        XCTAssertFalse(first.isSameDownload(as: second))
        second.versionID = nil
        second.platform = .ipad
        XCTAssertFalse(first.isSameDownload(as: second))
        XCTAssertTrue(first.canCancel)
        XCTAssertFalse(first.canRetry)
        second.status = .running
        XCTAssertFalse(second.canDelete)
        second.isCancelling = true
        XCTAssertFalse(second.canCancel)
        second.status = .cancelled
        second.isCancelling = false
        XCTAssertTrue(second.canRetry)
        XCTAssertTrue(second.canDelete)
        second.status = .failed
        XCTAssertTrue(second.canRetry)
    }
}
