import Foundation

/// Codable messages shared by Sora's app-side control layer and its bundled helper.
nonisolated enum SoraAutomationEndpoint {
    #if DEBUG
    static let helperIdentifier = "dev.ankitchouhan.sora.dev.helper"
    private static let directoryName = "sora-dev"
    #else
    static let helperIdentifier = "dev.ankitchouhan.sora.helper"
    private static let directoryName = "sora"
    #endif

    static let socketURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support", isDirectory: true)
        .appendingPathComponent(directoryName, isDirectory: true)
        .appendingPathComponent("automation.sock")
}

nonisolated enum SoraAutomationRequest: Codable, Equatable {
    case listSpaces
    case currentSpace(callerTerminalID: UUID)
    case createSpace(name: String, icon: String?, repositories: [String])
    case selectSpace(id: UUID)
    case renameSpace(id: UUID, name: String)
    case removeSpace(id: UUID, confirmed: Bool)
    case spawnTerminalInSpace(space: SoraSpaceReference, command: String?, name: String?)

    // Compatibility for clients built before Projects became Spaces.
    case listProjects
    case openProject(path: String, name: String?)
    case selectProject(id: UUID)
    case spawnTerminal(project: SoraProjectReference, command: String?, name: String?)
    case sendInput(terminalID: UUID, text: String, submit: Bool)
    case readOutput(terminalID: UUID, lines: Int)
    case closeTerminal(id: UUID)
    case reportAgentState(terminalID: UUID, state: SoraAgentReportState)

    // Tab, pane, and agent operations are scoped by the invoking terminal's Space.
    case currentTab(callerTerminalID: UUID)
    case listTabs(callerTerminalID: UUID)
    case getTab(callerTerminalID: UUID, tabID: UUID)
    case createTerminalTab(
        callerTerminalID: UUID, name: String?, directory: String?, pinned: Bool, focus: Bool
    )
    case focusTab(callerTerminalID: UUID, tabID: UUID)
    case setTabPinned(callerTerminalID: UUID, tabID: UUID, pinned: Bool)

    case currentPane(callerTerminalID: UUID)
    case listPanes(callerTerminalID: UUID)
    case getPane(callerTerminalID: UUID, paneID: UUID)
    case splitPane(
        callerTerminalID: UUID, paneID: UUID?, edge: SoraPaneEdge,
        directory: String?, focus: Bool
    )
    case runInPane(callerTerminalID: UUID, paneID: UUID?, arguments: [String])
    case sendPaneInput(callerTerminalID: UUID, paneID: UUID?, text: String, submit: Bool)
    case readPaneOutput(callerTerminalID: UUID, paneID: UUID?, lines: Int)
    case waitForPaneOutput(
        callerTerminalID: UUID, paneID: UUID?, contains: String,
        timeoutMilliseconds: Int, lines: Int
    )
    case focusPane(callerTerminalID: UUID, paneID: UUID?)

    case listAgents(callerTerminalID: UUID)
    case getAgent(callerTerminalID: UUID, target: SoraAgentTarget)
    case startAgent(
        callerTerminalID: UUID, paneID: UUID?, alias: String,
        kind: SoraAgentKind, arguments: [String], focus: Bool,
        timeoutMilliseconds: Int
    )
    case promptAgent(callerTerminalID: UUID, target: SoraAgentTarget, text: String)
    case readAgent(callerTerminalID: UUID, target: SoraAgentTarget, lines: Int)
    case waitForAgent(
        callerTerminalID: UUID, target: SoraAgentTarget,
        states: [SoraAgentState], timeoutMilliseconds: Int
    )
}

nonisolated enum SoraAgentReportState: String, Codable, Equatable {
    case working
    case blocked
    case idle
}

nonisolated enum SoraAgentKind: String, Codable, Equatable, CaseIterable {
    case claude
    case codex
    case gemini
    case grok
    case pi
    case cursorAgent = "cursor-agent"
    case openCode = "opencode"
    case copilot
    case kimi
    case amp

    var executable: String { rawValue }
}

nonisolated enum SoraAgentState: String, Codable, Equatable {
    case created
    case working
    case blocked
    case done
    case idle
    case unknown
}

nonisolated struct SoraAgentTarget: Codable, Equatable {
    var alias: String?
    var paneID: UUID?

    static func alias(_ alias: String) -> Self { Self(alias: alias, paneID: nil) }
    static func pane(_ id: UUID) -> Self { Self(alias: nil, paneID: id) }
}

nonisolated enum SoraPaneEdge: String, Codable, Equatable {
    case left
    case right
    case top
    case bottom
}

nonisolated enum SoraPaneContentKind: String, Codable, Equatable {
    case terminal
    case file
    case browser
    case diff
}

nonisolated struct SoraSpaceReference: Codable, Equatable {
    var id: UUID?
    var path: String?

    static func id(_ id: UUID) -> Self { Self(id: id, path: nil) }
    static func path(_ path: String) -> Self { Self(id: nil, path: path) }
}

nonisolated struct SoraProjectReference: Codable, Equatable {
    var id: UUID?
    var path: String?

    static func id(_ id: UUID) -> Self { Self(id: id, path: nil) }
    static func path(_ path: String) -> Self { Self(id: nil, path: path) }
}

nonisolated enum SoraAutomationResponse: Codable, Equatable {
    case success(SoraAutomationResult)
    case failure(SoraAutomationFailure)
}

nonisolated enum SoraAutomationResult: Codable, Equatable {
    case spaces([SoraSpaceSummary])
    case space(SoraSpaceSummary)
    case projects([SoraProjectSummary])
    case project(SoraProjectSummary)
    case terminal(SoraTerminalSummary)
    case tab(SoraTabSummary)
    case tabs([SoraTabSummary])
    case pane(SoraPaneSummary)
    case panes([SoraPaneSummary])
    case agent(SoraAgentSummary)
    case agents([SoraAgentSummary])
    case output(String)
    case acknowledged
}

nonisolated struct SoraSpaceSummary: Codable, Equatable {
    var id: UUID
    var windowID: UUID
    var name: String
    var icon: String?
    var repositories: [String]
    var selected: Bool
}

nonisolated struct SoraProjectSummary: Codable, Equatable {
    var id: UUID
    var windowID: UUID
    var name: String
    var directory: String?
    var selected: Bool
}

nonisolated struct SoraTerminalSummary: Codable, Equatable {
    var id: UUID
    var projectID: UUID
    var spaceID: UUID
    var name: String
    var directory: String
    var exited: Bool
}

nonisolated struct SoraTabSummary: Codable, Equatable {
    var id: UUID
    var spaceID: UUID
    var title: String
    var pinned: Bool
    var selected: Bool
    var paneCount: Int
}

nonisolated struct SoraPaneSummary: Codable, Equatable {
    var id: UUID
    var projectID: UUID
    var spaceID: UUID
    var tabID: UUID
    var terminalID: UUID?
    var title: String
    var content: SoraPaneContentKind
    var directory: String?
    var focused: Bool
    var caller: Bool
    var exited: Bool?
}

nonisolated struct SoraAgentSummary: Codable, Equatable {
    var alias: String
    var kind: SoraAgentKind
    var arguments: [String]
    var state: SoraAgentState
    var spaceID: UUID
    var tabID: UUID
    var paneID: UUID
    var terminalID: UUID
    var title: String
    var directory: String
    var focused: Bool
}

nonisolated struct SoraAutomationFailure: Error, Codable, Equatable {
    enum Code: String, Codable {
        case automationDisabled
        case invalidRequest
        case invalidPath
        case spaceNotFound
        case projectNotFound
        case tabNotFound
        case terminalNotFound
        case terminalExited
        case paneNotFound
        case paneNotTerminal
        case paneNotSplittable
        case shellBusy
        case aliasInUse
        case agentNotFound
        case agentNotRunning
        case agentBlocked
        case waitTimedOut
        case noWindow
        case outputUnavailable
        case internalError
    }

    var code: Code
    var message: String
}
