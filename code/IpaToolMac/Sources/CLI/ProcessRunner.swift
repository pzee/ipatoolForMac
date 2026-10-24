import Foundation
import Darwin

struct DownloadProgress: Equatable, Sendable {
    let percent: Int
    let detail: String

    static func parse(_ line: String) -> DownloadProgress? {
        // shortcut: ipatool exposes terminal progress text; use structured events when upstream provides them.
        let text = line.replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("downloading"),
              let range = text.range(of: #"^downloading\s+\d{1,3}%"#, options: .regularExpression),
              let percent = Int(text[range].dropFirst("downloading".count).dropLast().trimmingCharacters(in: .whitespaces)),
              (0...100).contains(percent) else { return nil }
        let detail = text.range(of: #"\([^)]*\)"#, options: .regularExpression)
            .map { String(text[$0].dropFirst().dropLast()) } ?? ""
        return DownloadProgress(percent: percent, detail: detail)
    }
}

struct CLIOutputBuffer {
    private var pending = Data()
    private var lastProgress: DownloadProgress?
    private(set) var text = ""

    mutating func append(_ data: Data, onProgress: ((DownloadProgress) -> Void)?) {
        pending.append(data)
        while let end = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            consume(String(decoding: pending[..<end], as: UTF8.self), onProgress: onProgress)
            pending.removeSubrange(...end)
        }
        // Terminal progress is prefixed by a carriage return and may have no trailing newline.
        reportProgress(String(decoding: pending, as: UTF8.self), onProgress: onProgress)
    }

    mutating func finish(onProgress: ((DownloadProgress) -> Void)?) {
        consume(String(decoding: pending, as: UTF8.self), onProgress: onProgress)
        pending.removeAll()
    }

    private mutating func consume(_ line: String, onProgress: ((DownloadProgress) -> Void)?) {
        if reportProgress(line, onProgress: onProgress) { return }
        if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text += line + "\n"
        }
    }

    @discardableResult
    private mutating func reportProgress(_ line: String, onProgress: ((DownloadProgress) -> Void)?) -> Bool {
        guard let progress = DownloadProgress.parse(line) else { return false }
        if progress != lastProgress {
            lastProgress = progress
            onProgress?(progress)
        }
        return true
    }
}

enum ProcessRunner {
    struct Result {
        var stdout: String
        var stderr: String
        var status: Int32
    }

    static func run(
        executable: URL,
        arguments: [String],
        onProgress: (@Sendable (DownloadProgress) -> Void)? = nil
    ) async throws -> Result {
        let execution = ProcessExecution()
        return try await withTaskCancellationHandler {
            let result = try await Task.detached(priority: .userInitiated) {
                let process = execution.process
                process.executableURL = executable
                process.arguments = arguments
                process.standardInput = FileHandle.nullDevice
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                try execution.start()
                let stdout = Task.detached { try drain(outPipe.fileHandleForReading, execution: execution, onProgress: onProgress) }
                let stderr = Task.detached { try drain(errPipe.fileHandleForReading, execution: execution, onProgress: onProgress) }
                process.waitUntilExit()
                return try await Result(stdout: stdout.value, stderr: stderr.value, status: process.terminationStatus)
            }.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            execution.cancel()
        }
    }

    private static func drain(
        _ handle: FileHandle,
        execution: ProcessExecution,
        onProgress: (@Sendable (DownloadProgress) -> Void)?
    ) throws -> String {
        defer { try? handle.close() }
        do {
            var buffer = CLIOutputBuffer()
            var bytes = [UInt8](repeating: 0, count: 16_384)
            while true {
                // FileHandle.read(upToCount:) waits for a full buffer on pipes.
                let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
                if count == 0 { break }
                if count < 0 {
                    if errno == EINTR { continue }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                buffer.append(Data(bytes.prefix(count)), onProgress: onProgress)
            }
            buffer.finish(onProgress: onProgress)
            return buffer.text
        } catch {
            execution.cancel()
            throw error
        }
    }
}

private final class ProcessExecution: @unchecked Sendable {
    let process = Process()
    private let lock = NSLock()
    private var cancelled = false

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        try process.run()
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
            lock.lock()
            defer { lock.unlock() }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}
