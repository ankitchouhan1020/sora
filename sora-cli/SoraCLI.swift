import Darwin
import Foundation

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case unavailable
    case transport(String)
    case remote(SoraAutomationFailure)

    var description: String {
        switch self {
        case .usage(let message): return message
        case .unavailable:
            return "Sora local automation is unavailable. Enable it in Sora → Settings → Automation."
        case .transport(let message): return message
        case .remote(let failure): return "\(failure.code.rawValue): \(failure.message)"
        }
    }
}

struct SoraClient: Sendable {
    func send(
        _ request: SoraAutomationRequest, launchIfNeeded: Bool = true
    ) throws -> SoraAutomationResult {
        if !FileManager.default.fileExists(atPath: SoraAutomationEndpoint.socketURL.path) {
            guard launchIfNeeded else { throw CLIError.unavailable }
            launchSora()
            waitForSocket()
        }

        do {
            return try sendOnce(request)
        } catch let error as CLIError {
            guard launchIfNeeded, case .transport = error else { throw error }
            launchSora()
            waitForSocket()
            return try sendOnce(request)
        }
    }

    private func sendOnce(_ request: SoraAutomationRequest) throws -> SoraAutomationResult {
        let descriptor = try connectedSocket()
        defer { Darwin.close(descriptor) }
        let payload = try JSONEncoder().encode(request)
        var length = UInt32(payload.count).bigEndian
        guard write(Data(bytes: &length, count: 4), to: descriptor),
              write(payload, to: descriptor),
              let header = read(count: 4, from: descriptor)
        else { throw CLIError.transport("Sora closed the automation connection") }
        let responseLength = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        guard responseLength > 0, responseLength <= 4 * 1024 * 1024,
              let responseData = read(count: Int(responseLength), from: descriptor),
              let response = try? JSONDecoder().decode(SoraAutomationResponse.self, from: responseData)
        else { throw CLIError.transport("Sora returned an invalid automation response") }

        switch response {
        case .success(let result): return result
        case .failure(let failure): throw CLIError.remote(failure)
        }
    }

    private func launchSora() {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let app = executable.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard app.pathExtension == "app" else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [app.path]
        try? process.run()
        process.waitUntilExit()
    }

    private func waitForSocket() {
        for _ in 0..<50 {
            if let descriptor = try? connectedSocket() {
                Darwin.close(descriptor)
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func connectedSocket() throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw CLIError.transport(systemError("create socket")) }
        var noSigPipe: Int32 = 1
        _ = setsockopt(
            descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe,
            socklen_t(MemoryLayout.size(ofValue: noSigPipe))
        )

        let path = SoraAutomationEndpoint.socketURL.path
        guard path.utf8CString.count <= MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            Darwin.close(descriptor)
            throw CLIError.transport("Sora automation socket path is too long")
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: path.utf8CString.count) { destination in
                path.withCString { _ = strncpy(destination, $0, path.utf8CString.count) }
            }
        }
        let length = socklen_t(
            MemoryLayout<sockaddr_un>.offset(of: \sockaddr_un.sun_path)! + path.utf8CString.count
        )
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, length)
            }
        }
        guard connected == 0 else {
            let error = systemError("connect to Sora")
            Darwin.close(descriptor)
            throw CLIError.transport(error)
        }
        return descriptor
    }

    private func systemError(_ action: String) -> String {
        "Failed to \(action): \(String(cString: strerror(errno)))"
    }

    private func read(count: Int, from descriptor: Int32) -> Data? {
        var data = Data(count: count)
        let received = data.withUnsafeMutableBytes { buffer -> Int in
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
        return received == count ? data : nil
    }

    private func write(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return data.isEmpty }
            var offset = 0
            while offset < buffer.count {
                let result = Darwin.write(
                    descriptor, base.advanced(by: offset), buffer.count - offset
                )
                if result > 0 { offset += result }
                else if result < 0, errno == EINTR { continue }
                else { return false }
            }
            return true
        }
    }
}

@main
private enum SoraCLI {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("sora: \(error)\n".utf8))
            Darwin.exit(error is CLIError ? 2 : 1)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else { throw CLIError.usage(usage) }
        if command == "pane",
           arguments.count == 1 || ["help", "--help", "-h"].contains(arguments[1]) {
            print(paneUsage)
            return
        }
        if command == "tab",
           arguments.count == 1 || ["help", "--help", "-h"].contains(arguments[1]) {
            print(tabUsage)
            return
        }
        if command == "agent",
           arguments.count == 1 || ["help", "--help", "-h"].contains(arguments[1]) {
            print(agentUsage)
            return
        }
        let client = SoraClient()
        switch command {
        case "status":
            guard arguments.count == 1 else { throw CLIError.usage("Usage: sora status") }
            let result = try client.send(.listSpaces, launchIfNeeded: false)
            guard case .spaces(let spaces) = result else { throw CLIError.transport("Unexpected response") }
            print("Sora is running; local automation enabled; \(spaces.count) Space(s)")
        case "space":
            try runSpaceCommand(Array(arguments.dropFirst()), client: client)
        case "tab":
            try runTabCommand(Array(arguments.dropFirst()), client: client)
        case "pane":
            try runPaneCommand(Array(arguments.dropFirst()), client: client)
        case "agent":
            try runAgentCommand(Array(arguments.dropFirst()), client: client)
        case "project":
            guard arguments == ["project", "list"] else {
                throw CLIError.usage("Usage: sora project list")
            }
            guard case .projects(let projects) = try client.send(.listProjects) else {
                throw CLIError.transport("Unexpected response")
            }
            for project in projects {
                print("\(project.id.uuidString)\t\(project.name)\t\(project.directory ?? "")")
            }
        case "open":
            guard arguments.count == 2 else { throw CLIError.usage("Usage: sora open <path>") }
            let path = absolutePath(arguments[1])
            guard case .project(let project) = try client.send(.openProject(path: path, name: nil))
            else { throw CLIError.transport("Unexpected response") }
            print("\(project.id.uuidString)\t\(project.name)\t\(project.directory ?? "")")
        case "send":
            guard (3...4).contains(arguments.count),
                  let id = UUID(uuidString: arguments[1]),
                  arguments.count == 3 || arguments[3] == "--submit"
            else { throw CLIError.usage("Usage: sora send <terminal-id> <text> [--submit]") }
            guard case .acknowledged = try client.send(.sendInput(
                terminalID: id, text: arguments[2], submit: arguments.count == 4
            )) else { throw CLIError.transport("Unexpected response") }
        case "output":
            guard arguments.count == 2 || (
                arguments.count == 4 && arguments[2] == "--lines"
                    && Int(arguments[3]) != nil
            ), let id = UUID(uuidString: arguments[1])
            else { throw CLIError.usage("Usage: sora output <terminal-id> [--lines <count>]") }
            let lines = arguments.count == 4 ? Int(arguments[3])! : 100
            guard case .output(let output) = try client.send(.readOutput(
                terminalID: id, lines: lines
            )) else { throw CLIError.transport("Unexpected response") }
            print(output)
        case "run":
            let parsed = try parseRun(Array(arguments.dropFirst()))
            guard case .terminal(let terminal) = try client.send(.spawnTerminalInSpace(
                space: parsed.space, command: parsed.command, name: parsed.name
            )) else { throw CLIError.transport("Unexpected response") }
            print("\(terminal.id.uuidString)\t\(terminal.name)\t\(terminal.directory)")
        case "help", "--help", "-h":
            print(usage)
        default:
            throw CLIError.usage(usage)
        }
    }

    private static func runSpaceCommand(_ arguments: [String], client: SoraClient) throws {
        guard let command = arguments.first else { throw CLIError.usage(spaceUsage) }
        switch command {
        case "current":
            guard arguments.count == 1,
                  case .space(let space) = try client.send(.currentSpace(
                    callerTerminalID: try callerTerminalID()
                  )) else { throw CLIError.usage(spaceUsage) }
            printJSON(space)
        case "get":
            guard arguments.count == 2, let id = UUID(uuidString: arguments[1]),
                  case .spaces(let spaces) = try client.send(.listSpaces),
                  let space = spaces.first(where: { $0.id == id })
            else { throw CLIError.usage(spaceUsage) }
            printJSON(space)
        case "list":
            guard arguments.count == 1,
                  case .spaces(let spaces) = try client.send(.listSpaces)
            else { throw CLIError.usage(spaceUsage) }
            printJSON(spaces)
        case "create":
            var name: String?
            var icon: String?
            var repositories: [String] = []
            var index = 1
            while index < arguments.count {
                guard index + 1 < arguments.count else { throw CLIError.usage(spaceUsage) }
                switch arguments[index] {
                case "--name": name = arguments[index + 1]
                case "--icon": icon = arguments[index + 1]
                case "--repository", "--repo":
                    repositories.append(absolutePath(arguments[index + 1]))
                default: throw CLIError.usage(spaceUsage)
                }
                index += 2
            }
            guard let name,
                  case .space(let space) = try client.send(.createSpace(
                    name: name, icon: icon, repositories: repositories
                  ))
            else { throw CLIError.usage(spaceUsage) }
            printJSON(space)
        case "select":
            guard arguments.count == 2, let id = UUID(uuidString: arguments[1]),
                  case .space(let space) = try client.send(.selectSpace(id: id))
            else { throw CLIError.usage(spaceUsage) }
            printJSON(space)
        case "rename":
            guard arguments.count == 3, let id = UUID(uuidString: arguments[1]),
                  case .space(let space) = try client.send(.renameSpace(
                    id: id, name: arguments[2]
                  ))
            else { throw CLIError.usage(spaceUsage) }
            printJSON(space)
        case "remove":
            guard arguments.count == 3, let id = UUID(uuidString: arguments[1]),
                  arguments[2] == "--force"
            else { throw CLIError.usage("Usage: sora space remove <id> --force") }
            guard case .acknowledged = try client.send(.removeSpace(id: id, confirmed: true))
            else { throw CLIError.transport("Unexpected response") }
        default:
            throw CLIError.usage(spaceUsage)
        }
    }

    private static func runTabCommand(
        _ arguments: [String], client: SoraClient
    ) throws {
        guard let command = arguments.first else { throw CLIError.usage(tabUsage) }
        let caller = try callerTerminalID()
        let result: SoraAutomationResult
        switch command {
        case "current":
            guard arguments.count == 1 else { throw CLIError.usage(tabUsage) }
            result = try client.send(.currentTab(callerTerminalID: caller))
        case "list":
            guard arguments.count == 1 else { throw CLIError.usage(tabUsage) }
            result = try client.send(.listTabs(callerTerminalID: caller))
        case "get":
            guard arguments.count == 2, let id = UUID(uuidString: arguments[1]) else {
                throw CLIError.usage(tabUsage)
            }
            result = try client.send(.getTab(callerTerminalID: caller, tabID: id))
        case "create":
            var name: String?
            var directory: String?
            var pinned: Bool?
            var focus = false
            var index = 1
            while index < arguments.count {
                switch arguments[index] {
                case "--name": name = try value(after: &index, in: arguments, option: "--name")
                case "--cwd": directory = absolutePath(try value(after: &index, in: arguments, option: "--cwd"))
                case "--pinned": pinned = true
                case "--temporary": pinned = false
                case "--focus": focus = true
                default: throw CLIError.usage(tabUsage)
                }
                index += 1
            }
            guard let pinned else {
                throw CLIError.usage("tab create requires --pinned or --temporary")
            }
            result = try client.send(.createTerminalTab(
                callerTerminalID: caller, name: name, directory: directory,
                pinned: pinned, focus: focus
            ))
        case "focus", "pin", "unpin":
            guard arguments.count == 2, let id = UUID(uuidString: arguments[1]) else {
                throw CLIError.usage(tabUsage)
            }
            result = command == "focus"
                ? try client.send(.focusTab(callerTerminalID: caller, tabID: id))
                : try client.send(.setTabPinned(
                    callerTerminalID: caller, tabID: id, pinned: command == "pin"
                ))
        default: throw CLIError.usage(tabUsage)
        }
        switch result {
        case .tab(let tab): printJSON(tab)
        case .tabs(let tabs): printJSON(tabs)
        default: throw CLIError.transport("Unexpected response")
        }
    }

    private static func runPaneCommand(
        _ arguments: [String], client: SoraClient
    ) throws {
        guard let command = arguments.first else { throw CLIError.usage(paneUsage) }
        let caller = try callerTerminalID()
        if command == "run" {
            let parsed = try parsePaneRun(Array(arguments.dropFirst()))
            guard case .acknowledged = try client.send(.runInPane(
                callerTerminalID: caller, paneID: parsed.paneID, arguments: parsed.arguments
            )) else { throw CLIError.transport("Unexpected response") }
            return
        }
        var paneID: UUID?
        var lines = 100
        var timeout = 30_000
        var text: String?
        var directory: String?
        var edge = SoraPaneEdge.right
        var submit = false
        var focus = false
        var options: Set<String> = []
        var index = 1
        while index < arguments.count {
            let option = arguments[index]
            options.insert(option)
            switch option {
            case "--current": paneID = nil
            case "--pane": paneID = try uuidValue(after: &index, in: arguments, option: option)
            case "--lines": lines = try intValue(after: &index, in: arguments, option: option)
            case "--timeout": timeout = try intValue(after: &index, in: arguments, option: option)
            case "--text", "--contains": text = try value(after: &index, in: arguments, option: option)
            case "--cwd": directory = absolutePath(try value(after: &index, in: arguments, option: option))
            case "--left": edge = .left
            case "--right": edge = .right
            case "--up", "--top": edge = .top
            case "--down", "--bottom": edge = .bottom
            case "--submit", "--enter": submit = true
            case "--focus": focus = true
            default: throw CLIError.usage(paneUsage)
            }
            index += 1
        }

        let result: SoraAutomationResult
        switch command {
        case "current":
            guard arguments.count == 1 else { throw CLIError.usage(paneUsage) }
            result = try client.send(.currentPane(callerTerminalID: caller))
        case "list":
            guard arguments.count == 1 else { throw CLIError.usage(paneUsage) }
            result = try client.send(.listPanes(callerTerminalID: caller))
        case "get":
            guard let paneID, options == ["--pane"] else { throw CLIError.usage(paneUsage) }
            result = try client.send(.getPane(callerTerminalID: caller, paneID: paneID))
        case "split":
            guard options.isSubset(of: [
                "--current", "--pane", "--cwd", "--left", "--right", "--up", "--top",
                "--down", "--bottom", "--focus",
            ]) else { throw CLIError.usage(paneUsage) }
            result = try client.send(.splitPane(
                callerTerminalID: caller, paneID: paneID, edge: edge,
                directory: directory, focus: focus
            ))
        case "send":
            guard let text, options.isSubset(of: [
                "--current", "--pane", "--text", "--submit", "--enter",
            ]) else { throw CLIError.usage(paneUsage) }
            result = try client.send(.sendPaneInput(
                callerTerminalID: caller, paneID: paneID, text: text, submit: submit
            ))
        case "read":
            guard options.isSubset(of: ["--current", "--pane", "--lines"])
            else { throw CLIError.usage(paneUsage) }
            result = try client.send(.readPaneOutput(
                callerTerminalID: caller, paneID: paneID, lines: lines
            ))
        case "wait":
            guard let text, options.isSubset(of: [
                "--current", "--pane", "--contains", "--timeout", "--lines",
            ]) else { throw CLIError.usage(paneUsage) }
            result = try client.send(.waitForPaneOutput(
                callerTerminalID: caller, paneID: paneID, contains: text,
                timeoutMilliseconds: timeout, lines: lines
            ))
        case "focus":
            guard options.isSubset(of: ["--current", "--pane"])
            else { throw CLIError.usage(paneUsage) }
            result = try client.send(.focusPane(
                callerTerminalID: caller, paneID: paneID
            ))
        default: throw CLIError.usage(paneUsage)
        }

        switch result {
        case .pane(let pane): printJSON(pane)
        case .panes(let panes): printJSON(panes)
        case .output(let output): print(output)
        case .acknowledged: break
        default: throw CLIError.transport("Unexpected response")
        }
    }

    private static func parsePaneRun(
        _ arguments: [String]
    ) throws -> (paneID: UUID?, arguments: [String]) {
        var paneID: UUID?
        var index = 0
        while index < arguments.count, arguments[index] != "--" {
            guard arguments[index] == "--pane" else { throw CLIError.usage(paneUsage) }
            paneID = try uuidValue(after: &index, in: arguments, option: "--pane")
            index += 1
        }
        guard index < arguments.count, arguments[index] == "--", index + 1 < arguments.count else {
            throw CLIError.usage(paneUsage)
        }
        return (paneID, Array(arguments.dropFirst(index + 1)))
    }

    private static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try! encoder.encode(value), as: UTF8.self))
    }

    private static func callerTerminalID() throws -> UUID {
        guard let value = ProcessInfo.processInfo.environment["SORA_TERMINAL_ID"],
              let id = UUID(uuidString: value) else {
            throw CLIError.usage("This command must run inside a Sora terminal.")
        }
        return id
    }

    private static func value(
        after index: inout Int, in arguments: [String], option: String
    ) throws -> String {
        index += 1
        guard index < arguments.count else { throw CLIError.usage("\(option) requires a value") }
        return arguments[index]
    }

    private static func intValue(
        after index: inout Int, in arguments: [String], option: String
    ) throws -> Int {
        let raw = try value(after: &index, in: arguments, option: option)
        guard let result = Int(raw), result > 0 else {
            throw CLIError.usage("\(option) requires a positive integer")
        }
        return result
    }

    private static func uuidValue(
        after index: inout Int, in arguments: [String], option: String
    ) throws -> UUID {
        let raw = try value(after: &index, in: arguments, option: option)
        guard let result = UUID(uuidString: raw) else {
            throw CLIError.usage("\(option) requires a pane UUID")
        }
        return result
    }

    private static func runAgentCommand(
        _ arguments: [String], client: SoraClient
    ) throws {
        guard let command = arguments.first else { throw CLIError.usage(agentUsage) }
        let tail = Array(arguments.dropFirst())
        switch command {
        case "list":
            guard tail.isEmpty,
                  case .agents(let agents) = try client.send(.listAgents(
                    callerTerminalID: try callerTerminalID()
                  )) else { throw CLIError.usage(agentUsage) }
            printJSON(agents)
        case "get":
            var index = 0
            let target = try parseAgentTarget(tail, index: &index)
            guard index == tail.count,
                  case .agent(let agent) = try client.send(.getAgent(
                    callerTerminalID: try callerTerminalID(), target: target
                  )) else { throw CLIError.usage(agentUsage) }
            printJSON(agent)
        case "start":
            try startAgent(tail, client: client)
        case "prompt":
            try promptAgent(tail, client: client)
        case "read":
            try readAgent(tail, client: client)
        case "wait":
            try waitForAgent(tail, client: client)
        case "state":
            guard tail.count == 1, let state = SoraAgentReportState(rawValue: tail[0]),
                  case .acknowledged = try client.send(
                    .reportAgentState(terminalID: try callerTerminalID(), state: state),
                    launchIfNeeded: false
                  ) else { throw CLIError.usage("Usage: sora agent state <working|blocked|idle>") }
        case "install", "uninstall":
            guard tail.count == 1 else { throw CLIError.usage(agentUsage) }
            try manageAgentIntegrations(action: command, name: tail[0])
        case "skill":
            try manageAgentSkill(tail)
        default:
            throw CLIError.usage(agentUsage)
        }
    }

    private static func startAgent(_ arguments: [String], client: SoraClient) throws {
        guard let alias = arguments.first, !alias.hasPrefix("--") else {
            throw CLIError.usage(agentUsage)
        }
        var paneID: UUID?
        var kind: SoraAgentKind?
        var focus = false
        var timeout = 30_000
        var extra: [String] = []
        var index = 1
        while index < arguments.count {
            if arguments[index] == "--" {
                extra = Array(arguments.dropFirst(index + 1))
                break
            }
            switch arguments[index] {
            case "--pane": paneID = try uuidValue(after: &index, in: arguments, option: "--pane")
            case "--kind":
                let raw = try value(after: &index, in: arguments, option: "--kind")
                kind = SoraAgentKind(rawValue: raw)
            case "--focus": focus = true
            case "--timeout": timeout = try intValue(after: &index, in: arguments, option: "--timeout")
            default: throw CLIError.usage(agentUsage)
            }
            index += 1
        }
        guard let kind, (3_000...300_000).contains(timeout),
              case .agent(let agent) = try client.send(.startAgent(
                callerTerminalID: try callerTerminalID(), paneID: paneID,
                alias: alias, kind: kind, arguments: extra, focus: focus,
                timeoutMilliseconds: timeout
              )) else { throw CLIError.usage(agentUsage) }
        printJSON(agent)
    }

    private static func promptAgent(_ arguments: [String], client: SoraClient) throws {
        var index = 0
        let target = try parseAgentTarget(arguments, index: &index)
        var text: String?
        var wait = false
        var timeout = 120_000
        while index < arguments.count {
            switch arguments[index] {
            case "--text": text = try value(after: &index, in: arguments, option: "--text")
            case "--wait": wait = true
            case "--timeout": timeout = try intValue(after: &index, in: arguments, option: "--timeout")
            default: throw CLIError.usage(agentUsage)
            }
            index += 1
        }
        guard let text, !text.isEmpty,
              case .agent(let submitted) = try client.send(.promptAgent(
                callerTerminalID: try callerTerminalID(), target: target, text: text
              )) else { throw CLIError.usage(agentUsage) }
        guard wait else { printJSON(submitted); return }
        guard case .agent(let completed) = try client.send(.waitForAgent(
            callerTerminalID: try callerTerminalID(), target: target,
            states: [.idle, .done, .blocked], timeoutMilliseconds: timeout
        )) else { throw CLIError.transport("Unexpected response") }
        printJSON(completed)
    }

    private static func readAgent(_ arguments: [String], client: SoraClient) throws {
        var index = 0
        let target = try parseAgentTarget(arguments, index: &index)
        var lines = 120
        while index < arguments.count {
            guard arguments[index] == "--lines" else { throw CLIError.usage(agentUsage) }
            lines = try intValue(after: &index, in: arguments, option: "--lines")
            index += 1
        }
        guard case .output(let output) = try client.send(.readAgent(
            callerTerminalID: try callerTerminalID(), target: target, lines: lines
        )) else { throw CLIError.transport("Unexpected response") }
        print(output)
    }

    private static func waitForAgent(_ arguments: [String], client: SoraClient) throws {
        var index = 0
        let target = try parseAgentTarget(arguments, index: &index)
        var states: [SoraAgentState] = [.idle, .done, .blocked]
        var timeout = 120_000
        while index < arguments.count {
            switch arguments[index] {
            case "--state":
                let raw = try value(after: &index, in: arguments, option: "--state")
                states = try raw.split(separator: ",").map {
                    guard let state = SoraAgentState(rawValue: String($0)) else {
                        throw CLIError.usage(agentUsage)
                    }
                    return state
                }
            case "--timeout": timeout = try intValue(after: &index, in: arguments, option: "--timeout")
            default: throw CLIError.usage(agentUsage)
            }
            index += 1
        }
        guard case .agent(let agent) = try client.send(.waitForAgent(
            callerTerminalID: try callerTerminalID(), target: target,
            states: states, timeoutMilliseconds: timeout
        )) else { throw CLIError.transport("Unexpected response") }
        printJSON(agent)
    }

    private static func parseAgentTarget(
        _ arguments: [String], index: inout Int
    ) throws -> SoraAgentTarget {
        guard index < arguments.count else { throw CLIError.usage(agentUsage) }
        if arguments[index] == "--pane" {
            let pane = try uuidValue(after: &index, in: arguments, option: "--pane")
            index += 1
            return .pane(pane)
        }
        guard !arguments[index].hasPrefix("--") else { throw CLIError.usage(agentUsage) }
        let alias = arguments[index]
        index += 1
        return .alias(alias)
    }

    private static func manageAgentIntegrations(action: String, name: String) throws {
        let integrations = try agentIntegrations(named: name)
        let files = try integrations.map { ($0, try $0.contents()) }
        for (integration, contents) in files {
            if let existing = try? Data(contentsOf: integration.destination), existing != contents {
                throw CLIError.usage(
                    "Refusing to overwrite conflicting \(integration.name) integration at \(integration.destination.path)"
                )
            }
        }
        for (integration, contents) in files {
            if action == "install" {
                try FileManager.default.createDirectory(
                    at: integration.destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try contents.write(to: integration.destination, options: .atomic)
                print("Installed \(integration.name) integration at \(integration.destination.path)")
            } else if FileManager.default.fileExists(atPath: integration.destination.path) {
                try FileManager.default.removeItem(at: integration.destination)
                print("Removed \(integration.name) integration from \(integration.destination.path)")
            }
        }
    }

    private static func manageAgentSkill(_ arguments: [String]) throws {
        guard let action = arguments.first, arguments.count <= 2 else {
            throw CLIError.usage(skillUsage)
        }
        let source = try bundledSkillURL()
        if action == "path" { print(source.path); return }
        if action == "print" {
            guard arguments.count == 1 else { throw CLIError.usage(skillUsage) }
            FileHandle.standardOutput.write(try Data(contentsOf: source))
            return
        }
        let provider = arguments.count == 2 ? arguments[1] : "all"
        let home = FileManager.default.homeDirectoryForCurrentUser
        let destinations: [URL] = switch provider {
        case "all": [
            home.appendingPathComponent(".agents/skills/sora-automation/SKILL.md"),
            home.appendingPathComponent(".claude/skills/sora-automation/SKILL.md"),
        ]
        case "shared": [home.appendingPathComponent(".agents/skills/sora-automation/SKILL.md")]
        case "claude": [home.appendingPathComponent(".claude/skills/sora-automation/SKILL.md")]
        default: throw CLIError.usage(skillUsage)
        }
        if action == "status" {
            printJSON(destinations.map { SkillStatus(
                path: $0.path, status: skillStatus(at: $0, source: source)
            ) })
            return
        }
        guard action == "install" || action == "uninstall" else {
            throw CLIError.usage(skillUsage)
        }
        for destination in destinations {
            if action == "install" {
                if FileManager.default.fileExists(atPath: destination.path) {
                    let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
                    guard values.isSymbolicLink == true,
                          destination.resolvingSymlinksInPath() == source.resolvingSymlinksInPath()
                    else { throw CLIError.usage("Refusing to replace modified skill at \(destination.path)") }
                    continue
                }
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: source)
            } else if FileManager.default.fileExists(atPath: destination.path) {
                let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values.isSymbolicLink == true,
                      destination.resolvingSymlinksInPath() == source.resolvingSymlinksInPath()
                else { throw CLIError.usage("Refusing to remove modified skill at \(destination.path)") }
                try FileManager.default.removeItem(at: destination)
            }
        }
        printJSON(destinations.map(\.path))
    }

    private struct SkillStatus: Codable { let path: String; let status: String }

    private static func skillStatus(at destination: URL, source: URL) -> String {
        guard FileManager.default.fileExists(atPath: destination.path) else { return "missing" }
        guard (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true,
              destination.resolvingSymlinksInPath() == source.resolvingSymlinksInPath()
        else { return "modified" }
        return "installed"
    }

    private static func bundledSkillURL() throws -> URL {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let resources = executable.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
        let candidates = [
            resources.appendingPathComponent("Skills/sora-automation/SKILL.md"),
            resources.appendingPathComponent("sora-automation/SKILL.md"),
            resources.appendingPathComponent("SKILL.md"),
        ]
        guard let source = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else { throw CLIError.unavailable }
        return source
    }

    private struct AgentIntegration {
        let name: String
        let destination: URL
        let bundledResource: String?

        func contents() throws -> Data {
            if let bundledResource {
                let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
                let resource = executable.deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("Resources/\(bundledResource)")
                guard let data = try? Data(contentsOf: resource) else { throw CLIError.unavailable }
                return data
            }
            return Data(piAgentExtension.utf8)
        }
    }

    private static func agentIntegrations(named name: String) throws -> [AgentIntegration] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let piBase = ProcessInfo.processInfo.environment["PI_CODING_AGENT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".pi/agent", isDirectory: true)
        let integrations = [
            AgentIntegration(
                name: "Pi",
                destination: piBase.appendingPathComponent("extensions/sora-agent-state.ts"),
                bundledResource: nil
            ),
            AgentIntegration(
                name: "OpenCode",
                destination: URL(fileURLWithPath:
                    ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
                        ?? home.appendingPathComponent(".config").path
                ).appendingPathComponent("opencode/plugins/sora-agent-state.js"),
                bundledResource: "sora-agent-state.js"
            ),
            AgentIntegration(
                name: "Grok",
                destination: URL(fileURLWithPath:
                    ProcessInfo.processInfo.environment["GROK_HOME"]
                        ?? home.appendingPathComponent(".grok").path
                ).appendingPathComponent("hooks/sora-agent-state.json"),
                bundledResource: "sora-agent-state.grok.json"
            ),
        ]
        if name == "all" { return integrations }
        guard let integration = integrations.first(where: { $0.name.lowercased() == name }) else {
            throw CLIError.usage(agentUsage)
        }
        return [integration]
    }

    private static func parseRun(
        _ arguments: [String]
    ) throws -> (space: SoraSpaceReference, name: String?, command: String) {
        var space: SoraSpaceReference?
        var name: String?
        var index = 0
        while index < arguments.count, arguments[index] != "--" {
            guard index + 1 < arguments.count else { throw CLIError.usage("Usage: \(runUsage)") }
            switch arguments[index] {
            case "--space", "--project":
                let value = arguments[index + 1]
                space = UUID(uuidString: value).map(SoraSpaceReference.id)
                    ?? .path(absolutePath(value))
            case "--name": name = arguments[index + 1]
            default: throw CLIError.usage("Usage: \(runUsage)")
            }
            index += 2
        }
        guard let space, index < arguments.count, arguments[index] == "--",
              index + 1 < arguments.count else { throw CLIError.usage("Usage: \(runUsage)") }
        let command = arguments[(index + 1)...].map(shellQuote).joined(separator: " ")
        return (space, name, command)
    }

    private static func absolutePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func shellQuote(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static let piAgentExtension = #"""
    // installed by Sora; reinstalling updates this file.
    import { execFile } from "node:child_process";
    import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

    const bin = process.env.SORA_BIN_PATH;
    const terminalID = process.env.SORA_TERMINAL_ID;
    const enabled = () => !!bin && !!terminalID;
    const report = (state: "working" | "blocked" | "idle") => {
      if (!enabled()) return;
      execFile(bin!, ["agent", "state", state], { timeout: 2000 }, () => {});
    };

    export default function (pi: ExtensionAPI) {
      let active = false;
      let blocked = 0;
      const publish = () => report(blocked > 0 ? "blocked" : active ? "working" : "idle");

      pi.events.on("herdr:blocked", (event: any) => {
        blocked = Math.max(0, blocked + (event?.active ? 1 : -1));
        publish();
      });
      pi.events.on("sora:blocked", (event: any) => {
        blocked = Math.max(0, blocked + (event?.active ? 1 : -1));
        publish();
      });
      pi.on("session_start", (_event, ctx) => {
        if (ctx.mode !== "tui") return;
        active = !ctx.isIdle();
        publish();
      });
      pi.on("agent_start", () => { active = true; publish(); });
      pi.on("agent_settled", (_event, ctx) => {
        if (ctx.isIdle()) { active = false; publish(); }
      });
    }
    """#

    private static let runUsage = "sora run --space <id-or-path> [--name <name>] -- <command> [arguments…]"
    private static let tabUsage = """
    Usage:
      sora tab current
      sora tab list
      sora tab get <id>
      sora tab create (--pinned|--temporary) [--name <name>] [--cwd <path>] [--focus]
      sora tab focus <id>
      sora tab pin <id>
      sora tab unpin <id>
    """
    private static let paneUsage = """
    Usage:
      sora pane current
      sora pane list
      sora pane get --pane <id>
      sora pane split [--pane <id>] [--left|--right|--up|--down] [--cwd <path>] [--focus]
      sora pane run [--pane <id>] -- <command> [arguments…]
      sora pane send [--pane <id>] --text <text> [--submit]    # raw terminal I/O
      sora pane read [--pane <id>] [--lines <count>]
      sora pane wait [--pane <id>] --contains <text> [--timeout <ms>] [--lines <count>]
      sora pane focus [--pane <id>]
    """
    private static let agentUsage = """
    Usage:
      sora agent list
      sora agent get <alias>|--pane <id>
      sora agent start <alias> --kind <kind> [--pane <id>] [--focus] [--timeout <ms>] [-- arguments…]
      sora agent prompt <alias>|--pane <id> --text <prompt> [--wait] [--timeout <ms>]
      sora agent read <alias>|--pane <id> [--lines <count>]
      sora agent wait <alias>|--pane <id> [--state idle,done,blocked] [--timeout <ms>]
      sora agent skill <path|print|status|install|uninstall> [all|shared|claude]
      sora agent install <pi|opencode|grok|all>
      sora agent uninstall <pi|opencode|grok|all>
      sora agent state <working|blocked|idle>

    Agent commands use the invoking terminal's Space. start requires an existing
    available shell and never creates layout. prompt never passes through a shell.
    """
    private static let skillUsage = "Usage: sora agent skill <path|print|status|install|uninstall> [all|shared|claude]"
    private static let spaceUsage = """
    Usage:
      sora space current
      sora space get <id>
      sora space list
      sora space create --name <name> [--icon <symbol>] [--repository <path>]…
      sora space select <id>
      sora space rename <id> <name>
      sora space remove <id> --force
    """
    private static let usage = """
    Usage:
      sora status
      sora space <current|get|list|create|select|rename|remove> [options]
      sora tab <current|get|list|create|focus|pin|unpin> [options]
      sora pane <current|get|list|split|run|send|read|wait|focus> [options]
      sora agent <list|get|start|prompt|read|wait|skill> [options]
      sora open <path>
      sora send <terminal-id> <text> [--submit]
      sora output <terminal-id> [--lines <count>]
      \(runUsage)
    """
}
