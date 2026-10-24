import Foundation

struct IPAToolService {
    func accountInfo() async throws -> AccountInfo {
        let envelope = try await run(["auth", "info"])
        guard let email = envelope.email, !email.isEmpty else {
            throw IPAToolError.failed(L10n.noAccount)
        }
        return AccountInfo(
            name: envelope.name ?? email,
            email: email,
            countryCode: StoreFront.countryCode(from: envelope.storeFront)
                ?? StoreFront.countryCode(from: StoreFront.accountStoreFront())
        )
    }

    func login(email: String, password: String, authCode: String?) async throws -> AccountInfo {
        var arguments = ["auth", "login", "--email", email, "--password", password]
        if let authCode, !authCode.isEmpty {
            arguments += ["--auth-code", authCode]
        }
        let envelope = try await run(arguments)
        if envelope.requiresAuthCode {
            throw IPAToolError.authCodeRequired
        }
        guard envelope.success != false else {
            throw IPAToolError.failed(envelope.errorMessage ?? L10n.unknownError)
        }
        return try await accountInfo()
    }

    func revoke() async throws {
        _ = try await run(["auth", "revoke"])
    }

    func search(term: String, platform: AppPlatform) async throws -> [StoreApp] {
        let envelope = try await run([
            "search", term,
            "--limit", String(platform.searchLimit),
            "--platform", platform.rawValue
        ])
        return (envelope.apps ?? []).map { app in
            var copy = app
            copy.platform = platform
            return copy
        }
    }

    func listPurchases(page: Int, limit: Int = PurchasePagination.pageSize) async throws -> PurchasePage {
        let envelope = try await run([
            "list-purchases",
            "--page", String(page),
            "--max-results", String(limit)
        ])
        return PurchasePage(
            apps: envelope.apps ?? [],
            count: envelope.count ?? envelope.apps?.count ?? 0,
            totalCount: envelope.totalCount ?? envelope.count ?? 0,
            page: envelope.page ?? page
        )
    }

    func purchase(bundleID: String) async throws -> Bool {
        let envelope = try await run(["purchase", "--bundle-identifier", bundleID])
        return envelope.alreadyOwned ?? false
    }

    func listVersions(app: StoreApp) async throws -> [String] {
        let envelope = try await run(["list-versions"] + appFlags(app))
        return envelope.externalVersionIdentifiers?.map(\.value) ?? []
    }

    func versionMetadata(app: StoreApp, versionID: String) async throws -> VersionInfo {
        let envelope = try await run(
            ["get-version-metadata", "--external-version-id", versionID] + appFlags(app)
        )
        return VersionInfo(
            versionID: envelope.externalVersionID ?? versionID,
            displayVersion: envelope.displayVersion,
            releaseDate: envelope.parsedReleaseDate
        )
    }

    func download(
        app: StoreApp,
        outputDirectory: URL,
        versionID: String?,
        purchaseIfNeeded: Bool,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> DownloadResult {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        // Publish only completed packages so cancellation cannot damage an existing IPA.
        let staging = outputDirectory.appendingPathComponent(".ipatool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        var arguments = [
            "download",
            "--output", staging.path
        ] + appFlags(app)
        if let platform = app.platform {
            arguments += ["--platform", platform.rawValue]
        }
        if let versionID, !versionID.isEmpty {
            arguments += ["--external-version-id", versionID]
        }
        if purchaseIfNeeded {
            arguments.append("--purchase")
        }
        let envelope = try await run(arguments, onProgress: onProgress)
        guard let output = envelope.output, !output.isEmpty else {
            throw IPAToolError.failed(L10n.downloadNoPath)
        }
        try Task.checkCancellation()
        let source = URL(fileURLWithPath: output)
        guard source.deletingLastPathComponent().standardizedFileURL.path == staging.standardizedFileURL.path,
              FileManager.default.fileExists(atPath: source.path) else {
            throw IPAToolError.failed(L10n.downloadNoPath)
        }
        let destination = Self.downloadDestination(app: app, fileExtension: source.pathExtension, directory: outputDirectory)
        try FileManager.default.moveItem(at: source, to: destination)
        return DownloadResult(outputPath: destination.path, purchased: envelope.purchased ?? false)
    }

    static func downloadDestination(app: StoreApp, fileExtension: String, directory: URL) -> URL {
        let cleaned = app.name.replacingOccurrences(of: #"[/\\:\p{Cc}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        var name = ""
        for character in cleaned {
            guard name.utf8.count + String(character).utf8.count <= 180 else { break }
            name.append(character)
        }
        if name.isEmpty { name = "App \(app.id)" }
        var destination = directory.appendingPathComponent(name).appendingPathExtension(fileExtension)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(name) (\(suffix))").appendingPathExtension(fileExtension)
            suffix += 1
        }
        return destination
    }

    private func appFlags(_ app: StoreApp) -> [String] {
        if !app.bundleID.isEmpty {
            return ["--bundle-identifier", app.bundleID]
        }
        return ["--app-id", String(app.id)]
    }

    private func run(
        _ arguments: [String],
        onProgress: (@Sendable (DownloadProgress) -> Void)? = nil
    ) async throws -> CLIEnvelope {
        let executable = try Self.resolveBinary()
        // ipatool suppresses progress in non-interactive mode; stdin stays closed in ProcessRunner.
        let flags = onProgress == nil ? ["--non-interactive"] : []
        let result = try await ProcessRunner.run(
            executable: executable,
            arguments: ["--format", "json"] + flags + arguments,
            onProgress: onProgress
        )
        let envelopes = CLIEnvelope.parseLines(result.stdout + "\n" + result.stderr)

        if let auth = envelopes.last(where: { $0.requiresAuthCode }) {
            return auth
        }
        if let failure = envelopes.last(where: { $0.success == false || $0.level == "error" }) {
            throw IPAToolError.failed(failure.errorMessage ?? L10n.unknownError)
        }
        if result.status != 0 {
            let message = envelopes.last?.errorMessage
                ?? result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw IPAToolError.failed(message.isEmpty ? String(format: L10n.ipatoolExitCode, result.status) : message)
        }
        if let last = envelopes.last {
            KeychainAccess.allowIpatoolWithoutPrompt()
            return last
        }
        throw IPAToolError.failed(L10n.ipatoolNoJSON)
    }

    static func resolveBinary() throws -> URL {
        let fallbacks = [
            "/opt/homebrew/bin/ipatool",
            "/usr/local/bin/ipatool"
        ]
        for path in fallbacks where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw IPAToolError.binaryNotFound
    }
}

struct CLIEnvelope: Decodable {
    var level: String?
    var success: Bool?
    fileprivate var error: FlexibleString?
    var message: String?
    var name: String?
    var email: String?
    var storeFront: String?
    var count: Int?
    var totalCount: Int?
    var page: Int?
    var apps: [StoreApp]?
    var output: String?
    var purchased: Bool?
    var alreadyOwned: Bool?
    var bundleID: String?
    fileprivate var externalVersionIdentifiers: [FlexibleString]?
    var externalVersionID: String?
    var displayVersion: String?
    fileprivate var releaseDate: FlexibleString?

    var errorMessage: String? {
        error?.value ?? message
    }

    var requiresAuthCode: Bool {
        let haystack = [message, error?.value].compactMap { $0 }.joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains("2FA")
            || haystack.localizedCaseInsensitiveContains("auth-code")
            || haystack.localizedCaseInsensitiveContains("auth code")
    }

    var parsedReleaseDate: Date? {
        releaseDate?.dateValue
    }

    static func parseLines(_ text: String) -> [CLIEnvelope] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeDate)
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
            return try? decoder.decode(CLIEnvelope.self, from: data)
        }
    }

    private static func decodeDate(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            return Date(timeIntervalSince1970: value)
        }
        let string = try container.decode(String.self)
        if let date = FlexibleString.parseDate(string) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date")
    }
}

private struct FlexibleString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
            return
        }
        if let int = try? container.decode(Int64.self) {
            value = String(int)
            return
        }
        if let double = try? container.decode(Double.self) {
            value = String(double)
            return
        }
        value = ""
    }

    var dateValue: Date? {
        Self.parseDate(value)
    }

    static func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: string) { return date }
        if let value = Double(string) {
            return Date(timeIntervalSince1970: value)
        }
        return nil
    }
}

extension StoreApp: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, bundleID, name, version, price, purchaseDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int64.self, forKey: .id) ?? 0
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
        price = try container.decodeIfPresent(Double.self, forKey: .price) ?? 0
        purchaseDate = try container.decodeIfPresent(Date.self, forKey: .purchaseDate)
        platform = nil
    }
}
