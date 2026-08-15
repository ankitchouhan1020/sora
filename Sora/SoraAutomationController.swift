import AppKit
import Foundation

/// Executes local automation requests against Sora's live window models.
@MainActor
enum SoraAutomationController {
    private static let maximumTextBytes = 64 * 1024
    private static let maximumOutputLines = 500

    static func handle(_ request: SoraAutomationRequest) -> SoraAutomationResponse {
        do {
            return .success(try execute(request))
        } catch let failure as SoraAutomationFailure {
            return .failure(failure)
        } catch {
            return .failure(.init(code: .internalError, message: error.localizedDescription))
        }
    }

    private static func execute(_ request: SoraAutomationRequest) throws -> SoraAutomationResult {
        switch request {
        case .listSpaces:
            return .spaces(TerminalManager.automationManagers.flatMap(spaceSummaries))
        case .createSpace(let name, let icon, let repositories):
            guard let name = try validateName(name) else {
                throw failure(.invalidRequest, "name is required")
            }
            let icon = try normalizeIcon(icon)
            let repositories = try repositories.map(canonicalRepository)
            guard let manager = TerminalManager.automationTargetManager else {
                throw failure(.noWindow, "Sora has no open window")
            }
            let space = manager.createSpace(name: name, icon: icon, repositories: repositories)
            manager.activateForAutomation()
            return .space(spaceSummary(space, in: manager))
        case .selectSpace(let id):
            let (manager, space) = try findSpace(id: id)
            select(space, in: manager)
            return .space(spaceSummary(space, in: manager))
        case .renameSpace(let id, let name):
            guard let name = try validateName(name) else {
                throw failure(.invalidRequest, "name is required")
            }
            let (manager, space) = try findSpace(id: id)
            space.customName = name
            return .space(spaceSummary(space, in: manager))
        case .removeSpace(let id, let confirmed):
            guard confirmed else {
                throw failure(.invalidRequest, "Space removal requires explicit confirmation")
            }
            let (manager, space) = try findSpace(id: id)
            manager.removeSpace(space)
            return .acknowledged
        case .spawnTerminalInSpace(let reference, let command, let name):
            let (manager, space) = try resolve(reference)
            if let command { try validateText(command, field: "command") }
            let name = try validateName(name)
            select(space, in: manager)
            let session = space.newSession(directory: space.customDirectory)
            space.selectedTab?.customName = name
            if let command, !command.isEmpty { session.sendCommand(command + "\r") }
            return .terminal(summary(session, in: space))
        case .listProjects:
            return .projects(TerminalManager.automationManagers.flatMap(projectSummaries))
        case .openProject(let path, let name):
            let (manager, project) = try openProject(path: path, name: name)
            return .project(summary(project, in: manager))
        case .selectProject(let id):
            let (manager, project) = try findProject(id: id)
            select(project, in: manager)
            return .project(summary(project, in: manager))
        case .spawnTerminal(let reference, let command, let name):
            let (manager, project) = try resolve(reference)
            if let command { try validateText(command, field: "command") }
            let name = try validateName(name)
            select(project, in: manager)
            let session = project.newSession(directory: project.customDirectory)
            project.selectedTab?.customName = name
            if let command, !command.isEmpty { session.sendCommand(command + "\r") }
            return .terminal(summary(session, in: project))
        case .sendInput(let terminalID, let text, let submit):
            try validateText(text, field: "text")
            let (_, _, session) = try findTerminal(id: terminalID)
            guard !session.hasExited else {
                throw failure(.terminalExited, "Terminal has exited")
            }
            session.sendCommand(text + (submit ? "\r" : ""))
            return .acknowledged
        case .readOutput(let terminalID, let lines):
            guard (1...maximumOutputLines).contains(lines) else {
                throw failure(
                    .invalidRequest,
                    "lines must be between 1 and \(maximumOutputLines)"
                )
            }
            let (_, _, session) = try findTerminal(id: terminalID)
            guard !session.hasExited else {
                throw failure(.terminalExited, "Terminal has exited")
            }
            guard let output = TerminalHistorySerializer.previewText(
                from: session.surface, maxLines: lines, maxColumns: 10_000
            ) else {
                throw failure(.outputUnavailable, "Terminal output is not available yet")
            }
            return .output(output)
        case .closeTerminal(let id):
            let (_, project, session) = try findTerminal(id: id)
            project.closeContent(.session(session))
            return .acknowledged
        case .reportAgentState(let terminalID, let state):
            let (manager, project, session) = try findTerminal(id: terminalID)
            let lifecycle: AgentLifecycleState = switch state {
            case .working: .working
            case .blocked: .blocked
            case .idle: .idle
            }
            session.reportAgentState(
                lifecycle,
                isVisible: manager.isViewing(session, in: project)
            )
            return .acknowledged
        }
    }

    private static func spaceSummaries(_ manager: TerminalManager) -> [SoraSpaceSummary] {
        manager.projects.map { spaceSummary($0, in: manager) }
    }

    private static func spaceSummary(_ space: Project, in manager: TerminalManager) -> SoraSpaceSummary {
        SoraSpaceSummary(
            id: space.id,
            windowID: manager.id,
            name: space.name,
            icon: space.customIcon,
            repositories: space.repositories.map(standardizedPath),
            selected: manager.selectedProjectID == space.id
        )
    }

    private static func projectSummaries(_ manager: TerminalManager) -> [SoraProjectSummary] {
        manager.projects.map { summary($0, in: manager) }
    }

    private static func summary(_ project: Project, in manager: TerminalManager) -> SoraProjectSummary {
        SoraProjectSummary(
            id: project.id,
            windowID: manager.id,
            name: project.name,
            directory: projectDirectory(project),
            selected: manager.selectedProjectID == project.id
        )
    }

    private static func summary(_ session: TerminalSession, in project: Project) -> SoraTerminalSummary {
        SoraTerminalSummary(
            id: session.id,
            projectID: project.id,
            name: project.tabs.first(where: { $0.sessions.contains { $0 === session } })?.displayTitle
                ?? session.title,
            directory: session.currentDirectoryPath,
            exited: session.hasExited
        )
    }

    private static func openProject(
        path: String, name: String?
    ) throws -> (TerminalManager, Project) {
        let path = try canonicalDirectory(path)
        let name = try validateName(name)
        if let match = TerminalManager.automationManagers.lazy.compactMap({ manager in
            manager.projects.first(where: { projectDirectory($0) == path }).map { (manager, $0) }
        }).first {
            select(match.1, in: match.0)
            return match
        }
        guard let manager = TerminalManager.automationTargetManager else {
            throw failure(.noWindow, "Sora has no open window")
        }
        let project = manager.newProject(directory: path, name: name)
        manager.activateForAutomation()
        return (manager, project)
    }

    private static func resolve(
        _ reference: SoraSpaceReference
    ) throws -> (TerminalManager, Project) {
        switch (reference.id, reference.path) {
        case (.some(let id), nil):
            return try findSpace(id: id)
        case (nil, .some(let path)):
            return try openProject(path: path, name: nil)
        default:
            throw failure(.invalidRequest, "Space reference requires exactly one id or path")
        }
    }

    private static func resolve(
        _ reference: SoraProjectReference
    ) throws -> (TerminalManager, Project) {
        switch (reference.id, reference.path) {
        case (.some(let id), nil):
            return try findProject(id: id)
        case (nil, .some(let path)):
            return try openProject(path: path, name: nil)
        default:
            throw failure(.invalidRequest, "Project reference requires exactly one id or path")
        }
    }

    private static func findSpace(id: UUID) throws -> (TerminalManager, Project) {
        for manager in TerminalManager.automationManagers {
            if let space = manager.projects.first(where: { $0.id == id }) {
                return (manager, space)
            }
        }
        throw failure(.spaceNotFound, "Space not found")
    }

    private static func findProject(id: UUID) throws -> (TerminalManager, Project) {
        for manager in TerminalManager.automationManagers {
            if let project = manager.projects.first(where: { $0.id == id }) {
                return (manager, project)
            }
        }
        throw failure(.projectNotFound, "Project not found")
    }

    private static func findTerminal(
        id: UUID
    ) throws -> (TerminalManager, Project, TerminalSession) {
        for manager in TerminalManager.automationManagers {
            for project in manager.projects {
                if let session = project.sessions.first(where: { $0.id == id }) {
                    return (manager, project, session)
                }
            }
        }
        throw failure(.terminalNotFound, "Terminal not found")
    }

    private static func select(_ project: Project, in manager: TerminalManager) {
        manager.selectedProjectID = project.id
        manager.activateForAutomation()
    }

    private static func projectDirectory(_ project: Project) -> String? {
        let path = project.customDirectory ?? project.selectedSession?.currentDirectoryPath
        return path.map(standardizedPath)
    }

    private static func canonicalRepository(_ path: String) throws -> String {
        let path = try canonicalDirectory(path)
        guard FileManager.default.fileExists(
            atPath: (path as NSString).appendingPathComponent(".git")
        ) else {
            throw failure(.invalidPath, "Space repositories must be Git repositories")
        }
        return path
    }

    private static func canonicalDirectory(_ path: String) throws -> String {
        guard path.hasPrefix("/") else {
            throw failure(.invalidPath, "Project path must be absolute")
        }
        let path = standardizedPath(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw failure(.invalidPath, "Project path must be an existing directory")
        }
        return path
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private static func normalizeIcon(_ icon: String?) throws -> String? {
        guard let icon = try validateName(icon) else { return nil }
        if icon.hasPrefix(SpaceIconValue.symbolPrefix) { return icon }
        return NSImage(systemSymbolName: icon, accessibilityDescription: nil) == nil
            ? icon
            : SpaceIconValue.symbol(icon)
    }

    private static func validateName(_ name: String?) throws -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200,
              trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { throw failure(.invalidRequest, "name must be 1–200 characters without controls") }
        return trimmed
    }

    private static func validateText(_ text: String, field: String) throws {
        guard text.utf8.count <= maximumTextBytes else {
            throw failure(.invalidRequest, "\(field) exceeds \(maximumTextBytes) bytes")
        }
    }

    private static func failure(
        _ code: SoraAutomationFailure.Code, _ message: String
    ) -> SoraAutomationFailure {
        .init(code: code, message: message)
    }
}
