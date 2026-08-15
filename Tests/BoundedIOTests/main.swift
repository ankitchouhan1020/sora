import Foundation

let temporary = FileManager.default.temporaryDirectory
    .appendingPathComponent("sora-bounded-io-tests-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

let largeFile = temporary.appendingPathComponent("large.txt")
let largeHandle = try FileHandle(forWritingTo: {
    FileManager.default.createFile(atPath: largeFile.path, contents: nil)
    return largeFile
}())
try largeHandle.truncate(atOffset: 2 << 20)
try largeHandle.close()
if case .tooLarge = BoundedIO.readFile(at: largeFile, limit: 1024) {
    // Expected: the size check runs before payload allocation.
} else {
    assertionFailure("oversized file was read")
}
if case .data(let data) = BoundedIO.readFile(at: largeFile, limit: nil) {
    assert(data.count == 2 << 20, "unlimited image-style reads remain supported")
} else {
    assertionFailure("unlimited read failed")
}

let cancelledRead = Task.detached {
    BoundedIO.readFile(at: largeFile, limit: nil)
}
cancelledRead.cancel()
if case .cancelled = await cancelledRead.value {
    // Expected.
} else {
    assertionFailure("cancelled read continued")
}

let noisy = BoundedProcess.run(
    executable: URL(fileURLWithPath: "/bin/sh"),
    arguments: ["-c", "yes x | head -c 1048576"],
    directory: temporary,
    environment: ProcessInfo.processInfo.environment,
    stdoutLimit: 4096,
    stderrLimit: 1024,
    timeout: 2
)
assert(noisy.stdout.count == 4096)
assert(noisy.stdoutTruncated)

let git = GitProcess.run(["--version"], in: temporary.path)
assert(git.status == 0)
assert(String(data: git.stdout, encoding: .utf8)?.hasPrefix("git version ") == true)

let start = Date()
let slow = BoundedProcess.run(
    executable: URL(fileURLWithPath: "/bin/sh"),
    arguments: ["-c", "sleep 5"],
    directory: temporary,
    environment: ProcessInfo.processInfo.environment,
    stdoutLimit: 1024,
    stderrLimit: 1024,
    timeout: 0.1
)
assert(slow.timedOut)
assert(Date().timeIntervalSince(start) < 2, "timeout retained the subprocess")

let cancellable = Task.detached {
    BoundedProcess.run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "sleep 5"],
        directory: temporary,
        environment: ProcessInfo.processInfo.environment,
        stdoutLimit: 1024,
        stderrLimit: 1024,
        timeout: 10
    )
}
try await Task.sleep(for: .milliseconds(50))
cancellable.cancel()
let cancelledProcess = await cancellable.value
assert(cancelledProcess.cancelled)

print("Bounded I/O tests passed")
