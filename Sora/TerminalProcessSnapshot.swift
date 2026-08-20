//
//  TerminalProcessSnapshot.swift
//  sora
//

import Darwin
import Foundation

nonisolated enum AgentKind: String {
    case claude
    case codex
    case gemini
    case grok
    case pi
    case cursorAgent
    case openCode
    case copilot
    case kimi
    case amp

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .grok: return "Grok"
        case .pi: return "Pi"
        case .cursorAgent: return "Cursor"
        case .openCode: return "OpenCode"
        case .copilot: return "Copilot"
        case .kimi: return "Kimi"
        case .amp: return "Amp"
        }
    }

    private static let aliases: [String: Self] = [
        "claude": .claude,
        "codex": .codex,
        "gemini": .gemini,
        "grok": .grok,
        "pi": .pi,
        "cursor-agent": .cursorAgent,
        "opencode": .openCode,
        "copilot": .copilot,
        "github-copilot": .copilot,
        "kimi": .kimi,
        "kimi-cli": .kimi,
        "amp": .amp,
    ]

    fileprivate static func classify(_ member: TerminalProcessSnapshot.Member) -> Self? {
        let executable = member.argv0.map(basename) ?? ""
        if let kind = aliases[member.name]
            ?? aliases[executable]
            ?? member.argv0.flatMap(resolvedAlias)
        { return kind }

        guard isWrapper(member.name) || isWrapper(executable),
              let arguments = member.argv?.dropFirst(),
              let first = arguments.first
        else { return nil }
        let wrapped = first == "--" ? arguments.dropFirst().first : first
        guard let wrapped, !wrapped.hasPrefix("-") else { return nil }
        return aliases[basename(wrapped)]
    }

    private static func basename(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// Cursor ships a generic `agent` symlink. Only trust it when its actual
    /// target has a known agent name; `agent` by itself is far too broad.
    private static func resolvedAlias(_ path: String) -> Self? {
        guard path.contains("/") else { return nil }
        return aliases[URL(fileURLWithPath: path).resolvingSymlinksInPath().lastPathComponent]
    }

    private static func isWrapper(_ name: String) -> Bool {
        ["node", "bun", "python", "python3", "sh", "bash", "zsh", "fish", "dash"]
            .contains(name) || name.hasPrefix("python3.")
    }
}

enum AgentLifecycleState: Equatable {
    case working
    case blocked
    case idle
}

enum AgentDisplayState: Equatable {
    case blocked
    case working
    case done
    case idle
    case unknown

    var label: String {
        switch self {
        case .blocked: return "Needs Input"
        case .working: return "Working"
        case .done: return "Done"
        case .idle: return "Idle"
        case .unknown: return "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .blocked: return "exclamationmark.circle.fill"
        case .working: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        case .idle: return "circle"
        case .unknown: return "questionmark.circle"
        }
    }

    var isRunning: Bool { self == .working }

    var priority: Int {
        switch self {
        case .blocked: return 5
        case .done: return 4
        case .working: return 3
        case .unknown: return 2
        case .idle: return 1
        }
    }
}

struct AgentStateTracker {
    private(set) var lifecycle: AgentLifecycleState?
    private(set) var completionUnseen = false

    var displayState: AgentDisplayState {
        switch lifecycle {
        case .blocked: return .blocked
        case .working: return .working
        case .idle: return completionUnseen ? .done : .idle
        case nil: return .unknown
        }
    }

    mutating func report(_ state: AgentLifecycleState, isVisible: Bool) {
        if state == .idle,
           lifecycle == .working || lifecycle == .blocked,
           !isVisible {
            completionUnseen = true
        } else if state != .idle || isVisible {
            completionUnseen = false
        }
        lifecycle = state
    }

    mutating func markSeen() {
        if lifecycle == .idle { completionUnseen = false }
    }

    mutating func reset() {
        lifecycle = nil
        completionUnseen = false
    }
}

enum TerminalActivity: Equatable {
    case agent(AgentKind)
    case command
    case terminal

    var agentKind: AgentKind? {
        if case .agent(let kind) = self { return kind }
        return nil
    }

    static func classify(
        shellPID: pid_t,
        foregroundPID: pid_t?,
        snapshot: TerminalProcessSnapshot?
    ) -> Self {
        let foregroundPID = foregroundPID ?? snapshot?.processGroupID
        guard let foregroundPID, foregroundPID != shellPID else { return .terminal }
        guard snapshot?.processGroupID == foregroundPID else { return .command }
        return snapshot?.agentKind.map(Self.agent) ?? .command
    }
}

/// Visible terminals update promptly; parked terminals and inactive windows
/// keep a slower heartbeat so background agents are still discovered without
/// every shell walking the process table twice a second.
nonisolated enum TerminalActivityMonitorPolicy {
    static func interval(isVisible: Bool, applicationIsActive: Bool) -> Duration {
        isVisible && applicationIsActive ? .milliseconds(500) : .seconds(2)
    }
}

/// Requires a stable second observation before publishing a transition. This
/// hides short-lived process metadata races when jobs start and exit.
struct TerminalActivityTracker {
    private(set) var activity: TerminalActivity = .terminal
    private var candidate: TerminalActivity?

    mutating func observe(_ observed: TerminalActivity) -> TerminalActivity? {
        guard observed != activity else {
            candidate = nil
            return nil
        }
        guard candidate == observed else {
            candidate = observed
            return nil
        }
        activity = observed
        candidate = nil
        return activity
    }
}

/// Best-effort metadata for the process group currently owning a terminal.
nonisolated struct TerminalProcessSnapshot: Equatable {
    struct Member: Equatable, Identifiable {
        var id: pid_t { pid }
        let pid: pid_t
        let name: String
        let argv: [String]?

        var argv0: String? { argv?.first }
    }

    let processGroupID: pid_t
    let members: [Member]

    var agentKind: AgentKind? {
        let leader = members.first { $0.pid == processGroupID }
        return ([leader].compactMap { $0 } + members.filter { $0.pid != processGroupID })
            .lazy.compactMap(AgentKind.classify).first
    }

    private static let maximumProcessCount = 65_536
    private static let maximumArgumentBytes = 1_048_576

    /// A login shell is ready for injected input only once it owns the
    /// foreground process group alone and is sleeping for terminal input.
    /// This avoids writing automation commands into shell startup files.
    static func isShellAwaitingInput(_ shellPID: pid_t) -> Bool {
        guard let info = bsdInfo(for: shellPID), info.pbi_status == SSLEEP,
              let snapshot = capture(shellPID: shellPID),
              snapshot.processGroupID == shellPID,
              snapshot.members.count == 1,
              snapshot.members[0].pid == shellPID else { return false }
        return true
    }

    /// Resolves the shell's foreground process group, then snapshots its
    /// members. Races and inaccessible kernel metadata fail closed.
    static func capture(shellPID: pid_t) -> Self? {
        guard shellPID > 0, let shell = bsdInfo(for: shellPID) else { return nil }
        let processGroupID = pid_t(shell.e_tpgid)
        guard processGroupID > 0, let pids = processIDs(in: processGroupID) else {
            return nil
        }

        let members = pids.compactMap { pid -> Member? in
            guard let info = bsdInfo(for: pid),
                  pid_t(info.pbi_pgid) == processGroupID
            else { return nil }
            return Member(pid: pid, name: processName(pid), argv: processArguments(pid))
        }.sorted { $0.pid < $1.pid }

        return Self(processGroupID: processGroupID, members: members)
    }

    private static func processIDs(in processGroupID: pid_t) -> [pid_t]? {
        let count = Int(proc_listpgrppids(processGroupID, nil, 0))
        guard count > 0, count < maximumProcessCount else { return nil }

        var pids = [pid_t](repeating: 0, count: min(count + 16, maximumProcessCount))
        let bytes = Int32(pids.count * MemoryLayout<pid_t>.size)
        let result = pids.withUnsafeMutableBufferPointer {
            proc_listpgrppids(processGroupID, $0.baseAddress, bytes)
        }
        guard result > 0, result < pids.count else { return nil }
        return Array(pids.prefix(Int(result))).filter { $0 > 0 }
    }

    private static func bsdInfo(for pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            return nil
        }
        return info
    }

    private static func processName(_ pid: pid_t) -> String {
        var bytes = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let count = bytes.withUnsafeMutableBufferPointer {
            proc_name(pid, $0.baseAddress, UInt32($0.count))
        }
        guard count > 0 else { return "" }
        return String(cString: bytes)
    }

    private static func processArguments(_ pid: pid_t) -> [String]? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0,
              size >= MemoryLayout<Int32>.size,
              size <= maximumArgumentBytes
        else { return nil }

        var bytes = [UInt8](repeating: 0, count: size)
        let result = bytes.withUnsafeMutableBytes {
            sysctl(&mib, UInt32(mib.count), $0.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return nil }
        return parseArguments(Array(bytes.prefix(size)))
    }

    /// Parses Darwin's KERN_PROCARGS2 format: argc, executable path, padding,
    /// then argc null-terminated argument strings.
    static func parseArguments(_ bytes: [UInt8]) -> [String]? {
        let width = MemoryLayout<Int32>.size
        guard bytes.count >= width else { return nil }
        let argc = bytes.prefix(width).enumerated().reduce(UInt32(0)) {
            $0 | UInt32($1.element) << UInt32($1.offset * 8)
        }
        guard argc <= bytes.count else { return nil }

        var cursor = width
        guard let executableEnd = bytes[cursor...].firstIndex(of: 0) else { return nil }
        cursor = executableEnd
        while cursor < bytes.count, bytes[cursor] == 0 { cursor += 1 }

        var arguments: [String] = []
        arguments.reserveCapacity(Int(argc))
        while arguments.count < Int(argc) {
            guard cursor < bytes.count,
                  let end = bytes[cursor...].firstIndex(of: 0)
            else { return nil }
            arguments.append(String(decoding: bytes[cursor..<end], as: UTF8.self))
            cursor = end + 1
        }
        return arguments
    }
}
