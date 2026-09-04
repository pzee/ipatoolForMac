import Foundation
import FMDB

final class DownloadStore {
    static let shared = DownloadStore()

    private let queue: FMDatabaseQueue

    private init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IPA Tool", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dbURL = root.appendingPathComponent("downloads.sqlite")
        queue = FMDatabaseQueue(path: dbURL.path)!
        queue.inDatabase { db in
            _ = db.executeUpdate(
                """
                CREATE TABLE IF NOT EXISTS downloads (
                    id TEXT PRIMARY KEY,
                    app_name TEXT NOT NULL,
                    bundle_id TEXT NOT NULL,
                    app_id INTEGER NOT NULL,
                    version_id TEXT,
                    platform TEXT,
                    purchase INTEGER NOT NULL,
                    status TEXT NOT NULL,
                    output_path TEXT,
                    error TEXT,
                    created_at REAL NOT NULL
                )
                """,
                withArgumentsIn: []
            )
        }
    }

    func loadAll() -> [DownloadJob] {
        var jobs: [DownloadJob] = []
        queue.inDatabase { db in
            guard let result = try? db.executeQuery(
                "SELECT * FROM downloads ORDER BY created_at DESC",
                values: []
            ) else { return }
            while result.next() {
                var job = DownloadJob(
                    id: UUID(uuidString: result.string(forColumn: "id") ?? "") ?? UUID(),
                    appName: result.string(forColumn: "app_name") ?? "",
                    bundleID: result.string(forColumn: "bundle_id") ?? "",
                    appID: result.longLongInt(forColumn: "app_id"),
                    versionID: result.string(forColumn: "version_id"),
                    platform: AppPlatform(rawValue: result.string(forColumn: "platform") ?? ""),
                    purchaseIfNeeded: result.bool(forColumn: "purchase"),
                    status: DownloadStatus(storage: result.string(forColumn: "status") ?? "failed"),
                    outputPath: result.string(forColumn: "output_path").flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) },
                    errorMessage: result.string(forColumn: "error"),
                    createdAt: Date(timeIntervalSince1970: result.double(forColumn: "created_at"))
                )
                if job.status == .running {
                    job.status = .failed
                    job.errorMessage = kL_downloadInterrupted
                }
                if job.errorMessage == "应用退出，下载中断" {
                    job.errorMessage = kL_downloadInterrupted
                }
                jobs.append(job)
            }
            result.close()
        }
        jobs.filter { $0.errorMessage == kL_downloadInterrupted }.forEach(upsert)
        let stale = jobs.filter { $0.status == .succeeded && !$0.fileExists }
        stale.forEach { delete($0.id) }
        return jobs.filter { job in stale.contains { $0.id == job.id } == false }
    }

    func delete(_ id: UUID) {
        queue.inDatabase { db in
            _ = db.executeUpdate(
                "DELETE FROM downloads WHERE id = ?",
                withArgumentsIn: [id.uuidString]
            )
        }
    }

    func upsert(_ job: DownloadJob) {
        queue.inDatabase { db in
            _ = db.executeUpdate(
                """
                INSERT OR REPLACE INTO downloads
                (id, app_name, bundle_id, app_id, version_id, platform, purchase, status, output_path, error, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                withArgumentsIn: [
                    job.id.uuidString,
                    job.appName,
                    job.bundleID,
                    NSNumber(value: job.appID),
                    job.versionID ?? NSNull(),
                    job.platform?.rawValue ?? NSNull(),
                    NSNumber(value: job.purchaseIfNeeded),
                    job.status.storage,
                    job.outputPath?.path ?? NSNull(),
                    job.errorMessage ?? NSNull(),
                    NSNumber(value: job.createdAt.timeIntervalSince1970)
                ]
            )
        }
    }
}

private extension DownloadStatus {
    var storage: String {
        switch self {
        case .queued: return "queued"
        case .running: return "running"
        case .succeeded: return "succeeded"
        case .failed: return "failed"
        }
    }

    init(storage: String) {
        switch storage {
        case "queued": self = .queued
        case "running": self = .running
        case "succeeded": self = .succeeded
        default: self = .failed
        }
    }
}
