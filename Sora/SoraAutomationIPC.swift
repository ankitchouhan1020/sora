import Darwin
import Foundation
import Security

/// A framed JSON control socket available only to Sora's bundled, signed helper.
@MainActor
final class SoraAutomationIPC {
    static let shared = SoraAutomationIPC()

    nonisolated private static let maximumRequestBytes = 128 * 1024
    nonisolated private let queue = DispatchQueue(label: "dev.ankitchouhan.sora.automation")
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?

    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    func stop() {
        if let source {
            source.cancel()
            self.source = nil
        } else if descriptor >= 0 {
            Darwin.close(descriptor)
        }
        descriptor = -1
        unlink(SoraAutomationEndpoint.socketURL.path)
    }

    private func start() {
        guard descriptor < 0 else { return }
        let path = SoraAutomationEndpoint.socketURL.path
        guard path.utf8CString.count <= MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        else {
            NSLog("Sora: local automation socket path is too long")
            return
        }

        let directory = SoraAutomationEndpoint.socketURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: directory.path
            )
        } catch {
            NSLog("Sora: failed to prepare local automation directory: \(error)")
            return
        }

        unlink(path)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            NSLog("Sora: failed to create local automation socket: \(String(cString: strerror(errno)))")
            return
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: path.utf8CString.count) { destination in
                path.withCString { source in
                    _ = strncpy(destination, source, path.utf8CString.count)
                }
            }
        }
        let addressLength = socklen_t(
            MemoryLayout<sockaddr_un>.offset(of: \sockaddr_un.sun_path)! + path.utf8CString.count
        )
        let didBind = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, addressLength)
            }
        }
        guard didBind == 0, listen(descriptor, 16) == 0 else {
            NSLog("Sora: failed to bind local automation socket: \(String(cString: strerror(errno)))")
            Darwin.close(descriptor)
            unlink(path)
            return
        }
        guard chmod(path, 0o600) == 0 else {
            NSLog("Sora: failed to secure local automation socket")
            Darwin.close(descriptor)
            unlink(path)
            return
        }

        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnections(on: descriptor) }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.activate()
        self.descriptor = descriptor
        self.source = source
    }

    nonisolated private func acceptConnections(on listener: Int32) {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            guard Self.trustedHelper(on: client) else {
                Darwin.close(client)
                continue
            }
            DispatchQueue.global().async { Self.handle(client) }
        }
    }

    nonisolated private static func handle(_ client: Int32) {
        defer { Darwin.close(client) }
        var noSigPipe: Int32 = 1
        _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout.size(ofValue: noSigPipe)))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        let timeoutSize = socklen_t(MemoryLayout.size(ofValue: timeout))
        _ = setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, timeoutSize)
        _ = setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, timeoutSize)

        guard let header = read(count: 4, from: client) else { return }
        let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        guard length > 0, length <= maximumRequestBytes,
              let data = read(count: Int(length), from: client),
              let request = try? JSONDecoder().decode(SoraAutomationRequest.self, from: data)
        else {
            write(.failure(.init(code: .invalidRequest, message: "Invalid automation request")), to: client)
            return
        }

        let response = DispatchQueue.main.sync {
            let isAgentReport = if case .reportAgentState = request { true } else { false }
            return AppSettings.shared.allowLocalAutomation || isAgentReport
                ? SoraAutomationController.handle(request)
                : .failure(.init(code: .automationDisabled, message: "Local automation is disabled"))
        }
        write(response, to: client)
    }

    nonisolated private static func trustedHelper(on socket: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(socket, &uid, &gid) == 0, uid == geteuid() else { return false }

        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout.size(ofValue: pid))
        guard getsockopt(socket, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0 else { return false }
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return false }
        guard let values = signingInformation(for: code),
              values[kSecCodeInfoIdentifier] as? String == SoraAutomationEndpoint.helperIdentifier
        else { return false }

        guard let expectedTeam = ownTeamIdentifier else { return true } // Debug ad-hoc signing.
        return values[kSecCodeInfoTeamIdentifier] as? String == expectedTeam
    }

    nonisolated private static var ownTeamIdentifier: String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        return signingInformation(for: code)?[kSecCodeInfoTeamIdentifier] as? String
    }

    nonisolated private static func signingInformation(
        for code: SecCode
    ) -> [CFString: Any]? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess
        else { return nil }
        return information as? [CFString: Any]
    }

    nonisolated private static func read(count: Int, from descriptor: Int32) -> Data? {
        var data = Data(count: count)
        let readCount = data.withUnsafeMutableBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            var offset = 0
            while offset < count {
                let result = Darwin.read(descriptor, base.advanced(by: offset), count - offset)
                if result > 0 { offset += result }
                else if result < 0, errno == EINTR { continue }
                else { return -1 }
            }
            return offset
        }
        return readCount == count ? data : nil
    }

    nonisolated private static func write(
        _ response: SoraAutomationResponse, to descriptor: Int32
    ) {
        guard let payload = try? JSONEncoder().encode(response) else { return }
        var length = UInt32(payload.count).bigEndian
        let header = withUnsafeBytes(of: &length) { Data($0) }
        for data in [header, payload] {
            let sent = data.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return 0 }
                var offset = 0
                while offset < buffer.count {
                    let result = Darwin.write(
                        descriptor, base.advanced(by: offset), buffer.count - offset
                    )
                    if result > 0 { offset += result }
                    else if result < 0, errno == EINTR { continue }
                    else { return -1 }
                }
                return offset
            }
            if sent != data.count { return }
        }
    }
}
