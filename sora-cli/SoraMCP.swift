import Foundation
import MCP

struct SoraMCP {
    static func run(client: SoraClient) async throws {
        let server = Server(
            name: "sora",
            version: "1.0",
            capabilities: .init(tools: .init())
        )

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: tools)
        }
        await server.withMethodHandler(CallTool.self) { parameters in
            await call(parameters, client: client)
        }

        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
        await server.stop()
    }

    private static func call(
        _ parameters: CallTool.Parameters, client: SoraClient
    ) async -> CallTool.Result {
        let arguments = parameters.arguments ?? [:]
        if arguments["pane_id"] != nil, uuid(arguments, "pane_id") == nil {
            return failure(.invalidRequest, "pane_id must be a UUID")
        }
        do {
            switch parameters.name {
            case "sora_current_pane":
                guard let caller = callerTerminalID() else { return callerFailure() }
                return try result(client.send(.currentPane(callerTerminalID: caller)))
            case "sora_list_panes":
                guard let caller = callerTerminalID() else { return callerFailure() }
                return try result(client.send(.listPanes(callerTerminalID: caller)))
            case "sora_split_pane":
                guard let caller = callerTerminalID() else { return callerFailure() }
                guard let edge = SoraPaneEdge(rawValue: arguments["edge"]?.stringValue ?? "right") else {
                    return failure(.invalidRequest, "edge must be left, right, top, or bottom")
                }
                return try result(client.send(.splitPane(
                    callerTerminalID: caller, paneID: uuid(arguments, "pane_id"), edge: edge,
                    directory: arguments["cwd"]?.stringValue.map(absolutePath),
                    focus: arguments["focus"]?.boolValue ?? false
                )))
            case "sora_send_pane_input":
                guard let caller = callerTerminalID() else { return callerFailure() }
                guard let text = arguments["text"]?.stringValue else {
                    return failure(.invalidRequest, "text is required")
                }
                return try result(client.send(.sendPaneInput(
                    callerTerminalID: caller, paneID: uuid(arguments, "pane_id"), text: text,
                    submit: arguments["submit"]?.boolValue ?? false
                )))
            case "sora_read_pane_output":
                guard let caller = callerTerminalID() else { return callerFailure() }
                return try result(client.send(.readPaneOutput(
                    callerTerminalID: caller, paneID: uuid(arguments, "pane_id"),
                    lines: arguments["lines"]?.intValue ?? 100
                )))
            case "sora_wait_for_pane_output":
                guard let caller = callerTerminalID() else { return callerFailure() }
                guard let contains = arguments["contains"]?.stringValue else {
                    return failure(.invalidRequest, "contains is required")
                }
                return try result(client.send(.waitForPaneOutput(
                    callerTerminalID: caller, paneID: uuid(arguments, "pane_id"), contains: contains,
                    timeoutMilliseconds: arguments["timeout_ms"]?.intValue ?? 30_000,
                    lines: arguments["lines"]?.intValue ?? 100
                )))
            case "sora_focus_pane":
                guard let caller = callerTerminalID() else { return callerFailure() }
                return try result(client.send(.focusPane(
                    callerTerminalID: caller, paneID: uuid(arguments, "pane_id")
                )))
            case "sora_report_agent_state":
                guard let caller = callerTerminalID() else { return callerFailure() }
                guard let rawState = arguments["state"]?.stringValue,
                      let state = SoraAgentReportState(rawValue: rawState) else {
                    return failure(.invalidRequest, "state must be working, blocked, or idle")
                }
                return try result(client.send(.reportAgentState(terminalID: caller, state: state)))
            case "sora_list_spaces":
                return try result(client.send(.listSpaces))
            case "sora_create_space":
                guard let name = arguments["name"]?.stringValue else {
                    return failure(.invalidRequest, "name is required")
                }
                let values = arguments["repositories"]?.arrayValue ?? []
                let repositories = values.compactMap(\.stringValue)
                guard repositories.count == values.count else {
                    return failure(.invalidRequest, "repositories must contain only paths")
                }
                return try result(client.send(.createSpace(
                    name: name,
                    icon: arguments["icon"]?.stringValue,
                    repositories: repositories.map(absolutePath)
                )))
            case "sora_select_space":
                guard let id = uuid(arguments, "space_id") else {
                    return failure(.invalidRequest, "space_id is required")
                }
                return try result(client.send(.selectSpace(id: id)))
            case "sora_rename_space":
                guard let id = uuid(arguments, "space_id"),
                      let name = arguments["name"]?.stringValue
                else { return failure(.invalidRequest, "space_id and name are required") }
                return try result(client.send(.renameSpace(id: id, name: name)))
            case "sora_remove_space":
                guard let id = uuid(arguments, "space_id"),
                      arguments["confirmed"]?.boolValue == true
                else { return failure(.invalidRequest, "space_id and confirmed=true are required") }
                return try result(client.send(.removeSpace(id: id, confirmed: true)))
            case "sora_list_projects":
                return try result(client.send(.listProjects))
            case "sora_open_project":
                guard let path = arguments["path"]?.stringValue else {
                    return failure(.invalidRequest, "path is required")
                }
                return try result(client.send(.openProject(
                    path: absolutePath(path), name: arguments["name"]?.stringValue
                )))
            case "sora_spawn_terminal":
                guard let space = arguments["space"]?.stringValue
                    ?? arguments["project"]?.stringValue else {
                    return failure(.invalidRequest, "space is required")
                }
                return try result(client.send(.spawnTerminalInSpace(
                    space: spaceReference(space),
                    command: arguments["command"]?.stringValue,
                    name: arguments["name"]?.stringValue
                )))
            case "sora_send_input":
                guard let id = uuid(arguments, "terminal_id"),
                      let text = arguments["text"]?.stringValue
                else { return failure(.invalidRequest, "terminal_id and text are required") }
                return try result(client.send(.sendInput(
                    terminalID: id, text: text,
                    submit: arguments["submit"]?.boolValue ?? false
                )))
            case "sora_read_output":
                guard let id = uuid(arguments, "terminal_id") else {
                    return failure(.invalidRequest, "terminal_id is required")
                }
                return try result(client.send(.readOutput(
                    terminalID: id, lines: arguments["lines"]?.intValue ?? 100
                )))
            case "sora_close_terminal":
                guard let id = uuid(arguments, "terminal_id") else {
                    return failure(.invalidRequest, "terminal_id is required")
                }
                return try result(client.send(.closeTerminal(id: id)))
            default:
                return failure(.invalidRequest, "Unknown tool: \(parameters.name)")
            }
        } catch CLIError.remote(let error) {
            return failure(error.code, error.message)
        } catch {
            return failure(.internalError, String(describing: error))
        }
    }

    private static func result(_ result: SoraAutomationResult) throws -> CallTool.Result {
        let value: Value
        switch result {
        case .spaces(let spaces):
            value = .object(["spaces": .array(spaces.map(spaceValue))])
        case .space(let space):
            value = .object(["space": spaceValue(space)])
        case .projects(let projects):
            value = .object(["projects": .array(projects.map(projectValue))])
        case .project(let project):
            value = .object(["project": projectValue(project)])
        case .terminal(let terminal):
            value = .object(["terminal": terminalValue(terminal)])
        case .pane(let pane):
            value = .object(["pane": paneValue(pane)])
        case .panes(let panes):
            value = .object(["panes": .array(panes.map(paneValue))])
        case .output(let output):
            value = .object(["output": .string(output)])
        case .acknowledged:
            value = .object(["ok": .bool(true)])
        }
        return .init(
            content: [.text(text: json(value), annotations: nil, _meta: nil)],
            structuredContent: Optional.some(value),
            isError: false
        )
    }

    private static func failure(
        _ code: SoraAutomationFailure.Code, _ message: String
    ) -> CallTool.Result {
        let value: Value = .object(["error": .object([
            "code": .string(code.rawValue), "message": .string(message),
        ])])
        return .init(
            content: [.text(text: json(value), annotations: nil, _meta: nil)],
            structuredContent: Optional.some(value),
            isError: true
        )
    }

    private static func spaceValue(_ space: SoraSpaceSummary) -> Value {
        .object([
            "id": .string(space.id.uuidString),
            "window_id": .string(space.windowID.uuidString),
            "name": .string(space.name),
            "icon": space.icon.map(Value.string) ?? .null,
            "repositories": .array(space.repositories.map(Value.string)),
            "selected": .bool(space.selected),
        ])
    }

    private static func projectValue(_ project: SoraProjectSummary) -> Value {
        .object([
            "id": .string(project.id.uuidString),
            "name": .string(project.name),
            "directory": project.directory.map(Value.string) ?? .null,
            "selected": .bool(project.selected),
        ])
    }

    private static func terminalValue(_ terminal: SoraTerminalSummary) -> Value {
        .object([
            "id": .string(terminal.id.uuidString),
            "space_id": .string(terminal.spaceID.uuidString),
            "project_id": .string(terminal.projectID.uuidString),
            "name": .string(terminal.name),
            "directory": .string(terminal.directory),
            "exited": .bool(terminal.exited),
        ])
    }

    private static func paneValue(_ pane: SoraPaneSummary) -> Value {
        .object([
            "id": .string(pane.id.uuidString),
            "project_id": .string(pane.projectID.uuidString),
            "tab_id": .string(pane.tabID.uuidString),
            "terminal_id": pane.terminalID.map { .string($0.uuidString) } ?? .null,
            "title": .string(pane.title),
            "content": .string(pane.content.rawValue),
            "directory": pane.directory.map(Value.string) ?? .null,
            "focused": .bool(pane.focused),
            "caller": .bool(pane.caller),
            "exited": pane.exited.map(Value.bool) ?? .null,
        ])
    }

    private static func callerTerminalID() -> UUID? {
        ProcessInfo.processInfo.environment["SORA_TERMINAL_ID"].flatMap(UUID.init(uuidString:))
    }

    private static func callerFailure() -> CallTool.Result {
        failure(.invalidRequest, "This tool must run inside a Sora terminal")
    }

    private static func uuid(_ arguments: [String: Value], _ key: String) -> UUID? {
        arguments[key]?.stringValue.flatMap(UUID.init(uuidString:))
    }

    private static func spaceReference(_ value: String) -> SoraSpaceReference {
        UUID(uuidString: value).map(SoraSpaceReference.id)
            ?? .path(absolutePath(value))
    }

    private static func projectReference(_ value: String) -> SoraProjectReference {
        UUID(uuidString: value).map(SoraProjectReference.id)
            ?? .path(absolutePath(value))
    }

    private static func absolutePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func json(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try! encoder.encode(value), as: UTF8.self)
    }

    private static let tools: [Tool] = [
        tool("sora_current_pane", "Get the invoking terminal pane"),
        tool("sora_list_panes", "List panes in the invoking terminal's project"),
        tool("sora_split_pane", "Split a terminal pane in the current project", properties: [
            "pane_id": string("Target pane UUID; defaults to the invoking pane"),
            "edge": string("left, right, top, or bottom; defaults to right"),
            "cwd": string("Directory for the new terminal"),
            "focus": boolean("Focus the new pane; defaults to false"),
        ]),
        tool("sora_send_pane_input", "Send raw input to a terminal pane", properties: [
            "pane_id": string("Target pane UUID; defaults to the invoking pane"),
            "text": string("Text to send"),
            "submit": boolean("Also send Enter"),
        ], required: ["text"]),
        tool("sora_read_pane_output", "Read terminal output without changing focus", properties: [
            "pane_id": string("Target pane UUID; defaults to the invoking pane"),
            "lines": integer("Lines to return (1–500)"),
        ]),
        tool("sora_wait_for_pane_output", "Wait until terminal output contains text", properties: [
            "pane_id": string("Target pane UUID; defaults to the invoking pane"),
            "contains": string("Text to wait for"),
            "timeout_ms": integer("Timeout in milliseconds (100–300000)"),
            "lines": integer("Lines to search (1–500)"),
        ], required: ["contains"]),
        tool("sora_focus_pane", "Focus a pane in the current project", properties: [
            "pane_id": string("Target pane UUID; defaults to the invoking pane"),
        ]),
        tool("sora_report_agent_state", "Report the invoking agent's trusted lifecycle state", properties: [
            "state": string("working, blocked, or idle"),
        ], required: ["state"]),
        tool("sora_list_spaces", "List Spaces open in Sora"),
        tool("sora_create_space", "Create a Sora Space", properties: [
            "name": string("Space name"),
            "icon": string("Optional emoji or SF Symbol name"),
            "repositories": .object([
                "type": "array",
                "description": "Git repository paths attached to the Space",
                "items": .object(["type": "string"]),
            ]),
        ], required: ["name"]),
        tool("sora_select_space", "Select a Sora Space", properties: [
            "space_id": string("Space UUID"),
        ], required: ["space_id"]),
        tool("sora_rename_space", "Rename a Sora Space", properties: [
            "space_id": string("Space UUID"),
            "name": string("New Space name"),
        ], required: ["space_id", "name"]),
        tool("sora_remove_space", "Permanently remove a Sora Space", properties: [
            "space_id": string("Space UUID"),
            "confirmed": .object([
                "type": "boolean",
                "description": "Must be true; removal closes terminals and loses unsaved edits",
            ]),
        ], required: ["space_id", "confirmed"]),
        tool("sora_list_projects", "Legacy alias: list projects open in Sora"),
        tool("sora_open_project", "Open or select a project directory in Sora", properties: [
            "path": string("Absolute or relative directory path"),
            "name": string("Optional project name"),
        ], required: ["path"]),
        tool("sora_spawn_terminal", "Open a visible terminal tab in a Sora Space", properties: [
            "space": string("Space UUID or repository path"),
            "project": string("Legacy alias for space"),
            "command": string("Optional shell command to run"),
            "name": string("Optional terminal tab name"),
        ]),
        tool("sora_send_input", "Send text to a live Sora terminal", properties: [
            "terminal_id": string("Terminal UUID"),
            "text": string("Text to send"),
            "submit": .object(["type": "boolean", "description": "Also send Enter"]),
        ], required: ["terminal_id", "text"]),
        tool("sora_read_output", "Read the bounded rendered tail of a Sora terminal", properties: [
            "terminal_id": string("Terminal UUID"),
            "lines": .object(["type": "integer", "description": "Lines to return (1–500)"]),
        ], required: ["terminal_id"]),
        tool("sora_close_terminal", "Close a Sora terminal tab", properties: [
            "terminal_id": string("Terminal UUID"),
        ], required: ["terminal_id"]),
    ]

    private static func tool(
        _ name: String, _ description: String,
        properties: [String: Value] = [:], required: [String] = []
    ) -> Tool {
        Tool(
            name: name,
            description: description,
            inputSchema: .object([
                "type": "object",
                "properties": .object(properties),
                "required": .array(required.map(Value.string)),
                "additionalProperties": false,
            ])
        )
    }

    private static func string(_ description: String) -> Value {
        .object(["type": "string", "description": .string(description)])
    }

    private static func boolean(_ description: String) -> Value {
        .object(["type": "boolean", "description": .string(description)])
    }

    private static func integer(_ description: String) -> Value {
        .object(["type": "integer", "description": .string(description)])
    }
}
