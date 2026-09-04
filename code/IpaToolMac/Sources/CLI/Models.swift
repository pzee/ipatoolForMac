import Foundation

enum SidebarSection: Int, CaseIterable {
    case search
    case purchases
    case downloads

    var title: String {
        switch self {
        case .search: return L10n.search
        case .purchases: return L10n.purchases
        case .downloads: return L10n.downloads
        }
    }

    var symbolName: String {
        switch self {
        case .search: return "magnifyingglass"
        case .purchases: return "bag"
        case .downloads: return "arrow.down.circle"
        }
    }
}

enum AppPlatform: String, CaseIterable {
    case iphone
    case ipad
    case appletv
    case visionos

    var title: String {
        switch self {
        case .iphone: return "iPhone"
        case .ipad: return "iPad"
        case .appletv: return "Apple TV"
        case .visionos: return "visionOS"
        }
    }

    var symbolName: String {
        switch self {
        case .iphone: return "iphone"
        case .ipad: return "ipad"
        case .appletv: return "appletv"
        case .visionos: return "vision.pro"
        }
    }

    var searchLimit: Int {
        self == .visionos ? 12 : 20
    }
}

struct AccountInfo: Equatable {
    var name: String
    var email: String
    var countryCode: String?
}

struct StoreApp: Equatable {
    var id: Int64
    var bundleID: String
    var name: String
    var version: String
    var price: Double
    var purchaseDate: Date?
    var platform: AppPlatform?

    var isFree: Bool { price == 0 }

    var displayName: String {
        name.isEmpty ? bundleID : name
    }

    var cellSubtitle: String {
        var parts: [String] = []
        if !version.isEmpty { parts.append(version) }
        if let purchaseDate {
            parts.append(String(format: L10n.purchasedSuffix, Formatters.day.string(from: purchaseDate)))
        } else {
            parts.append(Formatters.price(price))
        }
        return parts.joined(separator: " · ")
    }

    var getTitle: String {
        isFree ? L10n.get : Formatters.price(price)
    }
}

struct PurchasePage {
    var apps: [StoreApp]
    var count: Int
    var totalCount: Int
    var page: Int
}

struct VersionInfo {
    var versionID: String
    var displayVersion: String?
    var releaseDate: Date?
}

struct DownloadResult {
    var outputPath: String
    var purchased: Bool
}

enum DownloadStatus: Equatable {
    case queued
    case running
    case succeeded
    case failed

    var title: String {
        switch self {
        case .queued: return L10n.queued
        case .running: return L10n.running
        case .succeeded: return L10n.succeeded
        case .failed: return L10n.failed
        }
    }
}

struct DownloadJob: Equatable {
    let id: UUID
    var appName: String
    var bundleID: String
    var appID: Int64
    var versionID: String?
    var platform: AppPlatform?
    var purchaseIfNeeded: Bool
    var status: DownloadStatus
    var outputPath: URL?
    var errorMessage: String?
    var createdAt: Date

    var fileExists: Bool {
        guard let outputPath else { return false }
        return FileManager.default.fileExists(atPath: outputPath.path)
    }

    var canDelete: Bool {
        status != .running
    }
}

enum IPAToolError: LocalizedError {
    case binaryNotFound
    case authCodeRequired
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return L10n.binaryMissing
        case .authCodeRequired:
            return L10n.authCodeHint
        case .failed(let message):
            return message
        }
    }
}
