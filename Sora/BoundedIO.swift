//
//  BoundedIO.swift
//  sora
//

import Darwin
import Foundation

nonisolated enum BoundedFileRead: Sendable {
    case data(Data)
    case tooLarge
    case cancelled
    case failed
}

nonisolated enum BoundedIO {
    /// Reads one stable descriptor in chunks. A limit is checked before any
    /// payload allocation and again while reading in case the file grows.
    static func readFile(at url: URL, limit: Int?) -> BoundedFileRead {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let initialSize = try handle.seekToEnd()
            if let limit, initialSize > UInt64(limit) { return .tooLarge }
            guard initialSize < UInt64(Int.max) else { return limit == nil ? .failed : .tooLarge }
            try handle.seek(toOffset: 0)

            let captureLimit = limit.map { $0 + 1 } ?? (Int(initialSize) + 1)
            var data = Data()
            while data.count < captureLimit {
                if Task.isCancelled { return .cancelled }
                let count = min(64 * 1024, captureLimit - data.count)
                guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { break }
                data.append(chunk)
            }
            if Task.isCancelled { return .cancelled }
            if let limit, data.count > limit { return .tooLarge }
            // An unlimited read is used only for images. Do not chase a file
            // that is growing while it is being previewed.
            if limit == nil, data.count > Int(initialSize) { return .failed }
            return .data(data)
        } catch {
            return Task.isCancelled ? .cancelled : .failed
        }
    }
}

nonisolated struct BoundedProcessResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
    let stdoutTruncated: Bool
    let stderrTruncated: Bool
    let timedOut: Bool
    let cancelled: Bool
    let launchError: String?
}

private nonisolated final class ProcessCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data()
    private var wasTruncated = false
    private var reachedEOF = false

    func append(_ chunk: Data, limit: Int) {
        lock.lock()
        defer { lock.unlock() }
        let remaining = limit - value.count
        if remaining > 0 { value.append(chunk.prefix(remaining)) }
        if chunk.count > remaining { wasTruncated = true }
    }

    func markEOF() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !reachedEOF else { return false }
        reachedEOF = true
        return true
    }

    func snapshot() -> (Data, Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (value, wasTruncated)
    }
}

nonisolated enum BoundedProcess {
    /// Captures both pipes without blocking reader tasks. The subprocess is
    /// terminated on cancellation or timeout, and retained output never grows
    /// beyond the supplied per-pipe limits.
    static func run(
        executable: URL,
        arguments: [String],
        directory: URL,
        environment: [String: String],
        stdoutLimit: Int,
        stderrLimit: Int,
        timeout: TimeInterval
    ) -> BoundedProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdout = ProcessCapture()
        let stderr = ProcessCapture()
        let readers = DispatchGroup()
        readers.enter()
        readers.enter()
        let outHandle = stdoutPipe.fileHandleForReading
        let errHandle = stderrPipe.fileHandleForReading
        outHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                if stdout.markEOF() { readers.leave() }
            } else {
                stdout.append(chunk, limit: stdoutLimit)
            }
        }
        errHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                if stderr.markEOF() { readers.leave() }
            } else {
                stderr.append(chunk, limit: stderrLimit)
            }
        }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil
            return BoundedProcessResult(
                status: -1, stdout: Data(), stderr: Data(),
                stdoutTruncated: false, stderrTruncated: false,
                timedOut: false, cancelled: false,
                launchError: error.localizedDescription
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        var cancelled = false
        while finished.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            if Task.isCancelled {
                cancelled = true
                break
            }
            if Date() >= deadline {
                timedOut = true
                break
            }
        }
        if timedOut || cancelled {
            process.terminate()
            if finished.wait(timeout: .now() + .milliseconds(250)) == .timedOut,
               process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + .milliseconds(250))
            }
        } else {
            // EOF normally follows process termination immediately. A hook or
            // child retaining a pipe must not retain this call indefinitely.
            _ = readers.wait(timeout: .now() + .milliseconds(250))
        }

        outHandle.readabilityHandler = nil
        errHandle.readabilityHandler = nil
        try? outHandle.close()
        try? errHandle.close()
        let out = stdout.snapshot()
        let err = stderr.snapshot()
        return BoundedProcessResult(
            status: process.isRunning ? -1 : process.terminationStatus,
            stdout: out.0,
            stderr: err.0,
            stdoutTruncated: out.1,
            stderrTruncated: err.1,
            timedOut: timedOut,
            cancelled: cancelled,
            launchError: nil
        )
    }
}

nonisolated enum GitProcess {
    static let outputLimit = 5 << 20
    static let diagnosticLimit = 256 << 10
    static let readTimeout: TimeInterval = 15
    static let operationTimeout: TimeInterval = 120

    static func run(
        _ arguments: [String],
        in directory: String,
        stdoutLimit: Int = outputLimit,
        stderrLimit: Int = diagnosticLimit,
        timeout: TimeInterval = readTimeout,
        disableHooks: Bool = true
    ) -> BoundedProcessResult {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_ASKPASS"] = "/usr/bin/false"
        environment["SSH_ASKPASS"] = "/usr/bin/false"
        environment["GCM_INTERACTIVE"] = "Never"
        environment["GIT_EDITOR"] = "/usr/bin/true"
        environment["GIT_SEQUENCE_EDITOR"] = "/usr/bin/true"
        environment["GIT_PAGER"] = "cat"
        environment["LC_ALL"] = "C"
        let arguments = disableHooks
            ? ["-c", "core.hooksPath=/dev/null"] + arguments
            : arguments
        return BoundedProcess.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: arguments,
            directory: URL(fileURLWithPath: directory, isDirectory: true),
            environment: environment,
            stdoutLimit: stdoutLimit,
            stderrLimit: stderrLimit,
            timeout: timeout
        )
    }
}
