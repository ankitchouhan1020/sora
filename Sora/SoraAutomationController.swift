import AppKit
import Foundation

/// Executes local automation requests against Sora's live window models.
@MainActor
enum SoraAutomationController {
    private static let maximumTextBytes = 64 * 1024
    private static let maximumOutputLines = 500
    private static let maximumWaitMilliseconds = 300_000

    private struct PaneContext {
        let manager: TerminalManager
        let project: Project
        let tab: PaneTab
        let pane: Pane

        var session: TerminalSession? {
            if case .session(let session) = pane.content { return session }
            return nil
        }
    }

    static func handle(_ request: SoraAutomationRequest) async -> SoraAutomationResponse {
        do {
            return .success(try await execute(request))
        } catch let failure as SoraAutomationFailure {
            return .failure(failure)
        } catch {
            return .failure(.init(code: .internalError, message: error.localizedDescription))
        }
    }

    private static func execute(
        _ request: SoraAutomationRequest
    ) async throws -> SoraAutomationResult {
        switch request {
        case .listSpaces:
            return .spaces(TerminalManager.automationManagers.flatMap(spaceSummaries))
        case .currentSpace(let callerTerminalID):
            let caller = try callerContext(terminalID: callerTerminalID)
            return .space(spaceSummary(caller.project, in: caller.manager))
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
            let (_, _, session) = try findTerminal(id: terminalID)
            return .output(try output(from: session, lines: lines))
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
        case .currentTab(let callerTerminalID):
            let caller = try callerContext(terminalID: callerTerminalID)
            return .tab(tabSummary(caller.tab, in: caller.project))
        case .listTabs(let callerTerminalID):
            let caller = try callerContext(terminalID: callerTerminalID)
            return .tabs(caller.project.tabs.map { tabSummary($0, in: caller.project) })
        case .getTab(let callerTerminalID, let tabID):
            let caller = try callerContext(terminalID: callerTerminalID)
            return .tab(tabSummary(try targetTab(tabID, caller: caller), in: caller.project))
        case let .createTerminalTab(callerTerminalID, name, directory, pinned, shouldFocus):
            let caller = try callerContext(terminalID: callerTerminalID)
            let created = caller.project.automationCreateTerminalTab(
                directory: try directory.map(canonicalDirectory),
                name: try validateName(name), pinned: pinned, focus: shouldFocus
            )
            if shouldFocus {
                caller.manager.selectedProjectID = caller.project.id
                caller.manager.activateForAutomation()
            }
            return .tab(tabSummary(created.tab, in: caller.project))
        case .focusTab(let callerTerminalID, let tabID):
            let caller = try callerContext(terminalID: callerTerminalID)
            let tab = try targetTab(tabID, caller: caller)
            caller.project.selectedTabID = tab.id
            caller.manager.selectedProjectID = caller.project.id
            caller.manager.activateForAutomation()
            return .tab(tabSummary(tab, in: caller.project))
        case .setTabPinned(let callerTerminalID, let tabID, let pinned):
            let caller = try callerContext(terminalID: callerTerminalID)
            let tab = try targetTab(tabID, caller: caller)
            caller.project.setPinned(pinned, tabID: tab.id)
            return .tab(tabSummary(tab, in: caller.project))
        case .currentPane(let callerTerminalID):
            let caller = try callerContext(terminalID: callerTerminalID)
            return .pane(paneSummary(caller, callerPaneID: caller.pane.id))
        case .listPanes(let callerTerminalID):
            let caller = try callerContext(terminalID: callerTerminalID)
            return .panes(projectPaneContexts(caller.project, manager: caller.manager).map {
                paneSummary($0, callerPaneID: caller.pane.id)
            })
        case .getPane(let callerTerminalID, let paneID):
            let caller = try callerContext(terminalID: callerTerminalID)
            return .pane(paneSummary(
                try targetPane(paneID, caller: caller), callerPaneID: caller.pane.id
            ))
        case let .splitPane(callerTerminalID, paneID, edge, directory, shouldFocus):
            let caller = try callerContext(terminalID: callerTerminalID)
            let target = try targetPane(paneID, caller: caller)
            guard !target.pane.content.isDiff else {
                throw failure(.paneNotSplittable, "Diff panes cannot be split")
            }
            let directory = try directory.map(canonicalDirectory)
            guard let created = caller.project.automationSplitTerminal(
                beside: target.pane.id,
                toward: paneDropEdge(edge),
                directory: directory,
                focus: shouldFocus
            ) else {
                throw failure(.paneNotSplittable, "Pane could not be split")
            }
            let context = PaneContext(
                manager: caller.manager, project: caller.project,
                tab: created.tab, pane: created.pane
            )
            if shouldFocus { focus(context) }
            return .pane(paneSummary(context, callerPaneID: caller.pane.id))
        case let .runInPane(callerTerminalID, paneID, arguments):
            try validateArguments(arguments)
            let caller = try callerContext(terminalID: callerTerminalID)
            let session = try terminal(in: targetPane(paneID, caller: caller))
            guard session.canAcceptAutomationCommand else {
                throw failure(.shellBusy, "Commands require an available shell")
            }
            session.sendArguments(arguments)
            return .acknowledged
        case let .sendPaneInput(callerTerminalID, paneID, text, submit):
            try validateText(text, field: "text")
            let caller = try callerContext(terminalID: callerTerminalID)
            let session = try terminal(in: targetPane(paneID, caller: caller))
            session.sendCommand(text + (submit ? "\r" : ""))
            return .acknowledged
        case let .readPaneOutput(callerTerminalID, paneID, lines):
            let caller = try callerContext(terminalID: callerTerminalID)
            let session = try terminal(in: targetPane(paneID, caller: caller))
            return .output(try output(from: session, lines: lines))
        case let .waitForPaneOutput(
            callerTerminalID, paneID, needle, timeoutMilliseconds, lines
        ):
            guard !needle.isEmpty else {
                throw failure(.invalidRequest, "contains is required")
            }
            try validateText(needle, field: "contains")
            try validateLines(lines)
            guard (100...maximumWaitMilliseconds).contains(timeoutMilliseconds) else {
                throw failure(
                    .invalidRequest,
                    "timeoutMilliseconds must be between 100 and \(maximumWaitMilliseconds)"
                )
            }
            let caller = try callerContext(terminalID: callerTerminalID)
            let session = try terminal(in: targetPane(paneID, caller: caller))
            let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1_000)
            repeat {
                if let text = try? output(from: session, lines: lines), text.contains(needle) {
                    return .output(text)
                }
                if session.hasExited {
                    throw failure(.terminalExited, "Terminal has exited")
                }
                try await Task.sleep(for: .milliseconds(100))
            } while Date() < deadline
            throw failure(.waitTimedOut, "Timed out waiting for terminal output")
        case .focusPane(let callerTerminalID, let paneID):
            let caller = try callerContext(terminalID: callerTerminalID)
            let target = try targetPane(paneID, caller: caller)
            focus(target)
            return .pane(paneSummary(target, callerPaneID: caller.pane.id))
        case .listAgents(let callerTerminalID):
            let caller = try callerContext(terminalID: callerTerminalID)
            return .agents(try agentContexts(caller: caller).map(agentSummary))
        case .getAgent(let callerTerminalID, let target):
            let caller = try callerContext(terminalID: callerTerminalID)
            return .agent(try agentSummary(agentContext(target, caller: caller)))
        case let .startAgent(
            callerTerminalID, paneID, alias, kind, arguments, shouldFocus, timeoutMilliseconds
        ):
            let caller = try callerContext(terminalID: callerTerminalID)
            let target = try targetPane(paneID, caller: caller)
            let session = try terminal(in: target)
            guard validAlias(alias) else {
                throw failure(.invalidRequest, "alias must be 1–64 ASCII letters, numbers, dots, underscores, or hyphens")
            }
            guard !agentContexts(caller: caller).contains(where: {
                $0.session?.automationAgentAlias == alias && $0.session !== session
            }) else { throw failure(.aliasInUse, "Another agent in this Space uses alias \(alias)") }
            guard session.automationAgentAlias == nil, session.canAcceptAutomationCommand else {
                throw failure(.shellBusy, "Agent start requires an available terminal shell")
            }
            try validateArguments([kind.executable] + arguments)
            guard (3_000...maximumWaitMilliseconds).contains(timeoutMilliseconds) else {
                throw failure(.invalidRequest, "timeoutMilliseconds must be between 3000 and \(maximumWaitMilliseconds)")
            }
            let appKind = agentKind(kind)
            session.declareAutomationAgent(
                alias: alias, kind: appKind, arguments: [kind.executable] + arguments,
                timeoutMilliseconds: timeoutMilliseconds
            )
            if target.tab.customName == nil { target.tab.customName = alias }
            session.sendArguments([kind.executable] + arguments)
            if shouldFocus { focus(target) }
            let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1_000)
            repeat {
                if let detected = session.activity.agentKind {
                    guard detected == appKind else {
                        throw failure(.agentNotRunning, "Terminal launched \(detected.displayName), not \(kind.rawValue)")
                    }
                    return .agent(try agentSummary(target))
                }
                if session.automationAgentAlias == nil {
                    throw failure(.agentNotRunning, "Agent exited before Sora recognized it")
                }
                try await Task.sleep(for: .milliseconds(100))
            } while Date() < deadline
            throw failure(.waitTimedOut, "Timed out waiting for \(kind.rawValue) to start")
        case .promptAgent(let callerTerminalID, let target, let text):
            try validateText(text, field: "text")
            guard !text.isEmpty else { throw failure(.invalidRequest, "text is required") }
            let caller = try callerContext(terminalID: callerTerminalID)
            let context = try agentContext(target, caller: caller)
            let summary = try agentSummary(context)
            guard summary.state != .blocked else {
                throw failure(.agentBlocked, "Agent needs user input; automation cannot answer it")
            }
            guard context.session?.activity.agentKind != nil else {
                throw failure(.agentNotRunning, "Agent is not running")
            }
            context.session?.sendAutomationPrompt(text)
            return .agent(try agentSummary(context))
        case .readAgent(let callerTerminalID, let target, let lines):
            let caller = try callerContext(terminalID: callerTerminalID)
            let context = try agentContext(target, caller: caller)
            guard let session = context.session else {
                throw failure(.paneNotTerminal, "Agent pane is not a terminal")
            }
            return .output(try output(from: session, lines: lines))
        case let .waitForAgent(callerTerminalID, target, states, timeoutMilliseconds):
            guard !states.isEmpty, (100...3_600_000).contains(timeoutMilliseconds) else {
                throw failure(.invalidRequest, "states and timeoutMilliseconds are invalid")
            }
            let caller = try callerContext(terminalID: callerTerminalID)
            let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1_000)
            repeat {
                let context = try agentContext(target, caller: caller)
                let summary = try agentSummary(context)
                if states.contains(summary.state) { return .agent(summary) }
                try await Task.sleep(for: .milliseconds(100))
            } while Date() < deadline
            throw failure(.waitTimedOut, "Timed out waiting for agent state")
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
            spaceID: project.id,
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

    private static func callerContext(terminalID: UUID) throws -> PaneContext {
        for manager in TerminalManager.automationManagers {
            for project in manager.projects {
                for tab in project.tabs {
                    for pane in tab.allPanes {
                        guard case .session(let session) = pane.content,
                              session.id == terminalID else { continue }
                        return PaneContext(
                            manager: manager, project: project, tab: tab, pane: pane
                        )
                    }
                }
            }
        }
        throw failure(.terminalNotFound, "Invoking terminal is no longer open")
    }

    private static func targetTab(_ id: UUID, caller: PaneContext) throws -> PaneTab {
        guard let tab = caller.project.tabs.first(where: { $0.id == id }) else {
            throw failure(.tabNotFound, "Tab was not found in the invoking Space")
        }
        return tab
    }

    private static func tabSummary(_ tab: PaneTab, in project: Project) -> SoraTabSummary {
        SoraTabSummary(
            id: tab.id,
            spaceID: project.id,
            title: tab.displayTitle ?? "Untitled",
            pinned: tab.isPinned,
            selected: project.selectedTabID == tab.id,
            paneCount: tab.allPanes.count
        )
    }

    private static func projectPaneContexts(
        _ project: Project, manager: TerminalManager
    ) -> [PaneContext] {
        project.tabs.flatMap { tab in
            tab.allPanes.map {
                PaneContext(manager: manager, project: project, tab: tab, pane: $0)
            }
        }
    }

    private static func targetPane(
        _ paneID: UUID?, caller: PaneContext
    ) throws -> PaneContext {
        guard let paneID else { return caller }
        guard let target = projectPaneContexts(caller.project, manager: caller.manager)
            .first(where: { $0.pane.id == paneID }) else {
            throw failure(.paneNotFound, "Pane was not found in the invoking project")
        }
        return target
    }

    private static func terminal(in context: PaneContext) throws -> TerminalSession {
        guard let session = context.session else {
            throw failure(.paneNotTerminal, "Pane is not a terminal")
        }
        guard !session.hasExited else {
            throw failure(.terminalExited, "Terminal has exited")
        }
        return session
    }

    private static func paneSummary(
        _ context: PaneContext, callerPaneID: UUID
    ) -> SoraPaneSummary {
        let kind: SoraPaneContentKind = switch context.pane.content {
        case .session: .terminal
        case .file: .file
        case .browser: .browser
        case .diff: .diff
        }
        return SoraPaneSummary(
            id: context.pane.id,
            projectID: context.project.id,
            spaceID: context.project.id,
            tabID: context.tab.id,
            terminalID: context.session?.id,
            title: context.pane.content.title,
            content: kind,
            directory: context.session?.currentDirectoryPath,
            focused: context.manager.selectedProjectID == context.project.id
                && context.project.selectedTabID == context.tab.id
                && context.tab.focusedPaneID == context.pane.id,
            caller: context.pane.id == callerPaneID,
            exited: context.session?.hasExited
        )
    }

    private static func agentContexts(caller: PaneContext) -> [PaneContext] {
        projectPaneContexts(caller.project, manager: caller.manager).filter {
            guard let session = $0.session else { return false }
            return session.automationAgentAlias != nil || session.activity.agentKind != nil
        }
    }

    private static func agentContext(
        _ target: SoraAgentTarget, caller: PaneContext
    ) throws -> PaneContext {
        let matches = agentContexts(caller: caller)
        let context: PaneContext?
        switch (target.alias, target.paneID) {
        case (.some(let alias), nil):
            context = matches.first { $0.session?.automationAgentAlias == alias }
        case (nil, .some(let paneID)):
            context = matches.first { $0.pane.id == paneID }
        default:
            throw failure(.invalidRequest, "Agent target requires exactly one alias or pane ID")
        }
        guard let context else {
            throw failure(.agentNotFound, "Agent was not found in the invoking Space")
        }
        return context
    }

    private static func agentSummary(_ context: PaneContext) throws -> SoraAgentSummary {
        guard let session = context.session,
              let kind = session.activity.agentKind ?? session.automationAgentKind else {
            throw failure(.agentNotFound, "Pane is not running a recognized agent")
        }
        let state: SoraAgentState
        if session.activity.agentKind == nil {
            state = .created
        } else {
            state = switch session.agentState {
            case .blocked: .blocked
            case .working: .working
            case .done: .done
            case .idle: .idle
            case .unknown, nil: .unknown
            }
        }
        return SoraAgentSummary(
            alias: session.automationAgentAlias ?? automationAgentKind(kind).rawValue,
            kind: automationAgentKind(kind), arguments: session.automationAgentArguments,
            state: state,
            spaceID: context.project.id, tabID: context.tab.id,
            paneID: context.pane.id, terminalID: session.id,
            title: context.tab.displayTitle ?? context.pane.content.title,
            directory: session.currentDirectoryPath,
            focused: context.manager.selectedProjectID == context.project.id
                && context.project.selectedTabID == context.tab.id
                && context.tab.focusedPaneID == context.pane.id
        )
    }

    private static func agentKind(_ kind: SoraAgentKind) -> AgentKind {
        switch kind {
        case .claude: .claude
        case .codex: .codex
        case .gemini: .gemini
        case .grok: .grok
        case .pi: .pi
        case .cursorAgent: .cursorAgent
        case .openCode: .openCode
        case .copilot: .copilot
        case .kimi: .kimi
        case .amp: .amp
        }
    }

    private static func automationAgentKind(_ kind: AgentKind) -> SoraAgentKind {
        switch kind {
        case .claude: .claude
        case .codex: .codex
        case .gemini: .gemini
        case .grok: .grok
        case .pi: .pi
        case .cursorAgent: .cursorAgent
        case .openCode: .openCode
        case .copilot: .copilot
        case .kimi: .kimi
        case .amp: .amp
        }
    }

    private static func validAlias(_ alias: String) -> Bool {
        !alias.isEmpty && alias.utf8.count <= 64 && alias.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0)
                || (48...57).contains($0) || [45, 46, 95].contains($0)
        }
    }

    private static func focus(_ context: PaneContext) {
        context.manager.selectedProjectID = context.project.id
        context.project.selectedTabID = context.tab.id
        context.tab.focusedPaneID = context.pane.id
        context.manager.activateForAutomation()
    }

    private static func paneDropEdge(_ edge: SoraPaneEdge) -> PaneDropEdge {
        switch edge {
        case .left: .left
        case .right: .right
        case .top: .top
        case .bottom: .bottom
        }
    }

    private static func validateLines(_ lines: Int) throws {
        guard (1...maximumOutputLines).contains(lines) else {
            throw failure(
                .invalidRequest,
                "lines must be between 1 and \(maximumOutputLines)"
            )
        }
    }

    private static func output(from session: TerminalSession, lines: Int) throws -> String {
        try validateLines(lines)
        guard !session.hasExited else {
            throw failure(.terminalExited, "Terminal has exited")
        }
        guard let output = TerminalHistorySerializer.previewText(
            from: session.surface, maxLines: lines, maxColumns: 10_000
        ) else {
            throw failure(.outputUnavailable, "Terminal output is not available yet")
        }
        return output
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

    private static func validateArguments(_ arguments: [String]) throws {
        guard !arguments.isEmpty, arguments.count <= 128,
              arguments.allSatisfy({ argument in
                  argument.utf8.count <= 16_384 && argument.unicodeScalars.allSatisfy {
                      $0.value == 9 || !CharacterSet.controlCharacters.contains($0)
                  }
              }) else {
            throw failure(.invalidRequest, "arguments are empty, too large, or contain terminal controls")
        }
    }

    private static func failure(
        _ code: SoraAutomationFailure.Code, _ message: String
    ) -> SoraAutomationFailure {
        .init(code: code, message: message)
    }
}
