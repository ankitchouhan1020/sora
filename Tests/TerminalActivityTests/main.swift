import Darwin
import Foundation

private func snapshot(_ name: String, group: pid_t = 20) -> TerminalProcessSnapshot {
    TerminalProcessSnapshot(
        processGroupID: group,
        members: [.init(pid: group, name: name, argv: [name])]
    )
}

assert(TerminalActivity.classify(
    shellPID: 10, foregroundPID: 10, snapshot: snapshot("zsh", group: 10)
) == .terminal)
let claudeActivity = TerminalActivity.classify(
    shellPID: 10, foregroundPID: 20, snapshot: snapshot("claude")
)
assert(claudeActivity == .agent(.claude))
assert(claudeActivity.agentKind == .claude)
assert(claudeActivity.agentKind?.displayName == "Claude")
assert(TerminalActivity.classify(
    shellPID: 10, foregroundPID: nil, snapshot: snapshot("claude")
) == .agent(.claude))
assert(TerminalActivity.classify(
    shellPID: 10, foregroundPID: nil, snapshot: snapshot("zsh", group: 10)
) == .terminal)
let commandActivity = TerminalActivity.classify(
    shellPID: 10, foregroundPID: 20, snapshot: snapshot("git")
)
assert(commandActivity == .command)
assert(commandActivity.agentKind == nil)

assert(AgentDisplayState.working.isRunning)
assert(!AgentDisplayState.blocked.isRunning)
assert(!AgentDisplayState.done.isRunning)
assert(!AgentDisplayState.idle.isRunning)
assert(!AgentDisplayState.unknown.isRunning)

var agentState = AgentStateTracker()
assert(agentState.displayState == .unknown)
agentState.report(.working, isVisible: false)
assert(agentState.displayState == .working)
agentState.report(.blocked, isVisible: false)
assert(agentState.displayState == .blocked)
agentState.report(.idle, isVisible: false)
assert(agentState.displayState == .done)
agentState.markSeen()
assert(agentState.displayState == .idle)
agentState.report(.working, isVisible: false)
agentState.report(.idle, isVisible: true)
assert(agentState.displayState == .idle)
agentState.reset()
assert(agentState.displayState == .unknown)

var tracker = TerminalActivityTracker()
assert(tracker.observe(.agent(.claude)) == nil)
assert(tracker.observe(.agent(.claude)) == .agent(.claude))
assert(tracker.observe(.command) == nil)
assert(tracker.activity == .agent(.claude))
assert(tracker.observe(.agent(.claude)) == nil)
assert(tracker.observe(.terminal) == nil)
assert(tracker.observe(.terminal) == .terminal)

print("Terminal activity tests passed")
