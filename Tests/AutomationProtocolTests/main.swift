import Foundation

let caller = UUID()
let pane = UUID()
let requests: [SoraAutomationRequest] = [
    .currentPane(callerTerminalID: caller),
    .listPanes(callerTerminalID: caller),
    .splitPane(
        callerTerminalID: caller, paneID: pane, edge: .bottom,
        directory: "/tmp", focus: false
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

print("Automation protocol tests passed")
