import Foundation

struct EditorState: Codable {}
enum RightPanel: String, Codable { case files, git, beads, info }

let tab = SessionSnapshot.ProjectSnapshot.TabSnapshot(
    columns: [.init(
        panes: [.init(
            content: .session(workingDirectory: "/tmp"),
            weight: 1,
            historyKey: "stable-history-key"
        )],
        weight: 1
    )],
    focusedColumn: 0,
    focusedRow: 0,
    isPinned: true
)
let encoded = try JSONEncoder().encode(tab)
let restored = try JSONDecoder().decode(
    SessionSnapshot.ProjectSnapshot.TabSnapshot.self,
    from: encoded
)
assert(restored.isPinned == true)
assert(restored.columns[0].panes[0].historyKey == "stable-history-key")

var legacyObject = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
legacyObject.removeValue(forKey: "isPinned")
let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
let legacy = try JSONDecoder().decode(
    SessionSnapshot.ProjectSnapshot.TabSnapshot.self,
    from: legacyData
)
assert(legacy.isPinned == nil)

let project = SessionSnapshot.ProjectSnapshot(
    customName: "Ship auth",
    customIcon: "🚀",
    customDirectory: nil,
    repositories: ["/frontend", "/backend"],
    tabs: [],
    selectedTabIndex: nil
)
let projectData = try JSONEncoder().encode(project)
let restoredProject = try JSONDecoder().decode(
    SessionSnapshot.ProjectSnapshot.self,
    from: projectData
)
assert(restoredProject.repositories == ["/frontend", "/backend"])
assert(restoredProject.customIcon == "🚀")

var legacyProjectObject = try JSONSerialization.jsonObject(with: projectData) as! [String: Any]
legacyProjectObject.removeValue(forKey: "repositories")
legacyProjectObject.removeValue(forKey: "customIcon")
let legacyProjectData = try JSONSerialization.data(withJSONObject: legacyProjectObject)
let legacyProject = try JSONDecoder().decode(
    SessionSnapshot.ProjectSnapshot.self,
    from: legacyProjectData
)
assert(legacyProject.repositories == nil)
assert(legacyProject.customIcon == nil)
