import Foundation

var state = DiffReloadState()
assert(state.request())
assert(!state.request())
assert(!state.request())
assert(state.complete()) // Repeated requests coalesce into one follow-up.
assert(state.request())
state.cancel()
assert(!state.request()) // A revisit waits for cancellation to finish.
assert(state.complete())
assert(state.request())
state.cancel()
assert(!state.complete())

let cancellation = DiffReloadCancellation()
assert(!cancellation.isCancelled)
cancellation.cancel()
assert(cancellation.isCancelled)

print("Diff reload tests passed")
