import Foundation

let caller = UUID()
let pane = UUID()
let requests: [SoraAutomationRequest] = [
    .currentSpace(callerTerminalID: caller),
    .currentTab(callerTerminalID: caller),
    .listTabs(callerTerminalID: caller),
    .getTab(callerTerminalID: caller, tabID: UUID()),
    .createTerminalTab(
        callerTerminalID: caller, name: "review", directory: "/tmp",
        pinned: true, focus: false
    ),
    .focusTab(callerTerminalID: caller, tabID: UUID()),
    .setTabPinned(callerTerminalID: caller, tabID: UUID(), pinned: false),
    .currentPane(callerTerminalID: caller),
    .listPanes(callerTerminalID: caller),
    .getPane(callerTerminalID: caller, paneID: pane),
    .splitPane(
        callerTerminalID: caller, paneID: pane, edge: .bottom,
        directory: "/tmp", focus: false
    ),
    .runInPane(
        callerTerminalID: caller, paneID: pane,
        arguments: ["printf", "quote ' and \" double"]
    ),
    .sendPaneInput(
        callerTerminalID: caller, paneID: pane, text: "printf ok", submit: true
    ),
    .readPaneOutput(callerTerminalID: caller, paneID: pane, lines: 50),
    .waitForPaneOutput(
        callerTerminalID: caller, paneID: pane, contains: "ok",
        timeoutMilliseconds: 1_000, lines: 50
    ),
    .focusPane(callerTerminalID: caller, paneID: pane),
    .listAgents(callerTerminalID: caller),
    .getAgent(callerTerminalID: caller, target: .alias("review")),
    .startAgent(
        callerTerminalID: caller, paneID: pane, alias: "review", kind: .pi,
        arguments: ["--provider", "openai"], focus: false,
        timeoutMilliseconds: 30_000
    ),
    .promptAgent(
        callerTerminalID: caller, target: .alias("review"),
        text: "Review this.\nRun the focused check."
    ),
    .readAgent(callerTerminalID: caller, target: .pane(pane), lines: 120),
    .waitForAgent(
        callerTerminalID: caller, target: .alias("review"),
        states: [.idle, .done, .blocked], timeoutMilliseconds: 120_000
    ),
]

let encoder = JSONEncoder()
let decoder = JSONDecoder()
for request in requests {
    let encoded = try encoder.encode(request)
    let decoded = try decoder.decode(SoraAutomationRequest.self, from: encoded)
    assert(decoded == request)
}

let summary = SoraPaneSummary(
    id: pane,
    projectID: UUID(),
    spaceID: UUID(),
    tabID: UUID(),
    terminalID: caller,
    title: "zsh",
    content: .terminal,
    directory: "/tmp",
    focused: false,
    caller: true,
    exited: false
)
let response = SoraAutomationResponse.success(.pane(summary))
let encodedResponse = try encoder.encode(response)
let decodedResponse = try decoder.decode(SoraAutomationResponse.self, from: encodedResponse)
assert(decodedResponse == response)

let agent = SoraAgentSummary(
    alias: "review", kind: .pi, arguments: ["pi"], state: .working,
    spaceID: UUID(), tabID: UUID(), paneID: pane, terminalID: caller,
    title: "review", directory: "/tmp", focused: false
)
let agentResponse = SoraAutomationResponse.success(.agent(agent))
let encodedAgent = try encoder.encode(agentResponse)
let decodedAgent = try decoder.decode(SoraAutomationResponse.self, from: encodedAgent)
assert(decodedAgent == agentResponse)

print("Automation protocol tests passed")
