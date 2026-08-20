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

    // Pane operations are capability-scoped by the terminal invoking them.
    // A nil pane target means that invoking terminal's pane.
    case currentPane(callerTerminalID: UUID)
    case listPanes(callerTerminalID: UUID)
    case splitPane(
        callerTerminalID: UUID, paneID: UUID?, edge: SoraPaneEdge,
        directory: String?, focus: Bool
    )
    case sendPaneInput(
        callerTerminalID: UUID, paneID: UUID?, text: String, submit: Bool
    )
    case readPaneOutput(callerTerminalID: UUID, paneID: UUID?, lines: Int)
    case waitForPaneOutput(
        callerTerminalID: UUID, paneID: UUID?, contains: String,
        timeoutMilliseconds: Int, lines: Int
    )
    case focusPane(callerTerminalID: UUID, paneID: UUID?)
}

nonisolated enum SoraAgentReportState: String, Codable, Equatable {
    case working
    case blocked
    case idle
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
    case pane(SoraPaneSummary)
    case panes([SoraPaneSummary])
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
    var spaceID: UUID { projectID }
    var name: String
    var directory: String
    var exited: Bool
}

nonisolated struct SoraPaneSummary: Codable, Equatable {
    var id: UUID
    var projectID: UUID
    var tabID: UUID
    var terminalID: UUID?
    var title: String
    var content: SoraPaneContentKind
    var directory: String?
    var focused: Bool
    var caller: Bool
    var exited: Bool?
}

nonisolated struct SoraAutomationFailure: Error, Codable, Equatable {
    enum Code: String, Codable {
        case automationDisabled
        case invalidRequest
        case invalidPath
        case spaceNotFound
        case projectNotFound
        case terminalNotFound
        case terminalExited
        case paneNotFound
        case paneNotTerminal
        case paneNotSplittable
        case waitTimedOut
        case noWindow
        case outputUnavailable
        case internalError
    }

    var code: Code
    var message: String
}
