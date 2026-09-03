//
//  SidebarView.swift
//  sora
//

import AppKit
import SwiftUI

/// Arc-like Spaces navigation: one selected project (the current prototype's
/// Space) with stable pinned and temporary tabs arranged vertically.
struct SidebarView: View {
    @ObservedObject var manager: TerminalManager
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var themeChanges = Theme.changes
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("leftSidebarWidth") private var width: Double = 240

    @State private var isFullScreen = false
    @State private var draggedTabID: UUID?
    @State private var tabFrames: [UUID: CGRect] = [:]
    @State private var temporarySectionY = CGFloat.infinity
    @State private var swipeOffset: CGFloat = 0
    @State private var projectBeingRenamed: Project?
    @State private var renameDraft = ""
    @State private var tabBeingRenamed: PaneTab?
    @State private var tabRenameDraft = ""
    @State private var projectChangingIcon: Project?
    @State private var iconDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titlebar

            GeometryReader { geometry in
                ZStack {
                    if let project = manager.selectedProject {
                        spaceCanvas(project)
                            .frame(width: geometry.size.width)
                            .offset(x: reduceMotion ? 0 : swipeOffset)
                    }
                    if !reduceMotion, let adjacent = adjacentProject {
                        spaceCanvas(adjacent)
                            .frame(width: geometry.size.width)
                            .offset(x: adjacentOffset(for: geometry.size.width))
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }

            footer
        }
        .frame(width: width)
        .background(sidebarBackground)
        .overlay(alignment: .trailing) {
            if !Theme.isDefault(dark: colorScheme == .dark) {
                Rectangle()
                    .fill(Color(nsColor: Theme.divider))
                    .frame(width: 1)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .trailing) {
            SidebarResizeHandle(
                edge: .trailing,
                width: $width,
                range: 200...420,
                defaultWidth: 240
            )
        }
        .background {
            SpaceSwipeMonitor(
                onChanged: updateSpaceSwipe,
                onEnded: finishSpaceSwipe
            )
        }
        .onPreferenceChange(SidebarTabFramePreferenceKey.self) { tabFrames = $0 }
        .onPreferenceChange(SidebarTemporarySectionPreferenceKey.self) { temporarySectionY = $0 }
        .alert("Rename Space", isPresented: Binding(
            get: { projectBeingRenamed != nil },
            set: { if !$0 { projectBeingRenamed = nil } }
        )) {
            TextField("Space name", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Rename", action: commitRename)
                .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Rename Tab", isPresented: Binding(
            get: { tabBeingRenamed != nil },
            set: { if !$0 { tabBeingRenamed = nil } }
        )) {
            TextField("Tab name", text: $tabRenameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Rename", action: commitTabRename)
                .disabled(tabRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var titlebar: some View {
        HStack(spacing: 6) {
            if let project = manager.selectedProject {
                Text(project.name)
                    .font(.system(size: settings.sidebarFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            WindowDragArea()
                .frame(minWidth: 4, maxWidth: .infinity)
                .layoutPriority(-1)

            if manager.runningAgentCount > 0 {
                Button {
                    manager.showAgentsInCommandPalette()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: AgentDisplayState.working.systemImage)
                        Text("\(manager.runningAgentCount)")
                            .monospacedDigit()
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AgentDisplayState.working.color)
                    .padding(.horizontal, 5)
                    .frame(height: 22)
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Show running agents across Spaces")
                .accessibilityLabel("\(manager.runningAgentCount) running agents across Spaces")
            }

            Button {
                manager.presentSpaceCreator()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Space (⌘N)")
            .accessibilityLabel("New Space")
        }
        .padding(.leading, isFullScreen ? 8 : 78)
        .padding(.trailing, 8)
        .frame(height: 42)
        .background(FullScreenStateReader(isFullScreen: $isFullScreen))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: Theme.divider).opacity(0.6))
                .frame(height: 1)
        }
    }

    private func spaceCanvas(_ project: Project) -> some View {
        tabList(project)
            .contentShape(Rectangle())
            .contextMenu { spaceActions(for: project) }
    }

    private func tabList(_ project: Project) -> some View {
        let pinned = project.tabs.filter(\.isPinned)
        let temporary = project.tabs.filter { !$0.isPinned }

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    pinnedHeader(count: pinned.count)
                    ForEach(pinned) { tab in
                        tabRow(tab, project: project, isPinned: true)
                    }

                    Rectangle()
                        .fill(Color(nsColor: Theme.divider))
                        .frame(height: 1)
                        .padding(.horizontal, 8)
                        .padding(.top, 12)
                        .padding(.bottom, 5)

                    Button {
                        project.newSession()
                        if let tabID = project.selectedTabID {
                            project.setPinned(false, tabID: tabID)
                        }
                    } label: {
                        Label("New Terminal", systemImage: "terminal")
                            .font(.system(size: settings.sidebarFontSize))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("New Terminal (⌘T)")
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: SidebarTemporarySectionPreferenceKey.self,
                                value: proxy.frame(in: .global).minY
                            )
                        }
                    }

                    ForEach(temporary) { tab in
                        tabRow(tab, project: project, isPinned: false)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .onChange(of: project.selectedTabID) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    proxy.scrollTo(id)
                }
            }
        }
    }

    private func pinnedHeader(count: Int) -> some View {
        HStack(spacing: 5) {
            Text("PINNED")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text("\(count)")
                .font(.system(size: 9.5))
                .monospacedDigit()
                .foregroundStyle(.quaternary)
            Spacer()
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.top, 5)
        .padding(.bottom, 3)
    }

    private func tabRow(
        _ tab: PaneTab,
        project: Project,
        isPinned: Bool
    ) -> some View {
        let agentKind = tab.sessions.compactMap { $0.activity.agentKind }.first
        let agentState = tab.sessions.compactMap(\.agentState).max { $0.priority < $1.priority }
        return SidebarTabRow(
            tab: tab,
            agentKind: agentKind,
            agentState: agentState,
            isSelected: project.selectedTabID == tab.id,
            fontSize: settings.sidebarFontSize,
            select: { project.selectedTabID = tab.id },
            close: { project.close(tab) }
        )
        .id(tab.id)
        .contextMenu {
            Button("Rename…") { beginRename(tab) }
            if tab.customName != nil {
                Button("Use Automatic Title") { tab.customName = nil }
            }
            Button(isPinned ? "Unpin Tab" : "Pin Tab") {
                setPinned(!isPinned, tab: tab, project: project)
            }
            Divider()
            Button("Close") { project.close(tab) }
            Button("Close Others") { project.closeOthers(tab) }
                .disabled(project.tabs.count <= 1)
            Button("Close Tabs Below") { project.closeToRight(of: tab) }
                .disabled(project.tabs.last?.id == tab.id)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SidebarTabFramePreferenceKey.self,
                    value: [tab.id: proxy.frame(in: .global)]
                )
            }
        }
        .opacity(draggedTabID == tab.id ? 0.6 : 1)
        .highPriorityGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { value in
                    updateTabDrag(
                        source: tab.id,
                        location: value.location,
                        project: project
                    )
                }
                .onEnded { _ in endTabDrag() }
        )
    }

    private var spaceStrip: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(manager.projects.enumerated()), id: \.element.id) { index, project in
                        let isSelected = project.id == manager.selectedProjectID
                        let agentCount = project.agentSessions.count
                        Button {
                            manager.selectedProjectID = project.id
                        } label: {
                            Group {
                                if let icon = project.customIcon {
                                    SpaceIconGlyph(value: icon, size: 10)
                                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                                        .opacity(isSelected ? 1 : 0.62)
                                } else {
                                    Circle()
                                        .fill(isSelected ? Color.primary.opacity(0.9) : Color.secondary.opacity(0.42))
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .frame(width: project.customIcon == nil ? 14 : 18, height: 18)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(spaceHelp(project, index: index, agentCount: agentCount))
                        .accessibilityLabel(spaceAccessibilityLabel(project, agentCount: agentCount))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .contextMenu { spaceActions(for: project) }
                    }
                }
                .frame(minWidth: geometry.size.width)
            }
        }
        .frame(height: 18)
    }

    private func spaceHelp(_ project: Project, index: Int, agentCount: Int) -> String {
        let shortcut = "⌘\(min(index + 1, 9))"
        guard agentCount > 0 else { return "\(project.name) (\(shortcut))" }
        return "\(project.name) · \(agentCount) agent \(agentCount == 1 ? "session" : "sessions") open (\(shortcut))"
    }

    private func spaceAccessibilityLabel(_ project: Project, agentCount: Int) -> String {
        guard agentCount > 0 else { return "Space: \(project.name)" }
        return "Space: \(project.name), \(agentCount) open agent \(agentCount == 1 ? "session" : "sessions")"
    }

    private var footer: some View {
        HStack(spacing: 2) {
            SidebarFooterButton(systemImage: "magnifyingglass", tooltip: "Search Tabs (⌘P)") {
                manager.toggleCommandPalette()
            }

            if manager.projects.count > 1 {
                spaceStrip
                    .frame(maxWidth: .infinity)
            } else {
                Spacer()
            }

            Menu {
                if let project = manager.selectedProject {
                    spaceActions(for: project)
                    Divider()
                }
                Button("Settings…") { openSettings() }
                Button("Send Feedback") {
                    NSWorkspace.shared.open(
                        URL(string: "https://github.com/ankitchouhan1020/sora/issues/new")!
                    )
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .accessibilityLabel("More sidebar and Space actions")
            .popover(isPresented: Binding(
                get: { projectChangingIcon != nil },
                set: { if !$0 { projectChangingIcon = nil } }
            ), arrowEdge: .bottom) {
                SpaceIconPicker(selection: $iconDraft, onSelect: commitIcon)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: Theme.divider))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var sidebarBackground: some View {
        if Theme.isDefault(dark: colorScheme == .dark) {
            VisualEffectView(material: .sidebar)
        } else {
            Color(nsColor: Theme.sidebar)
        }
    }

    @ViewBuilder
    private func spaceActions(for project: Project) -> some View {
        Button("New Space") { manager.presentSpaceCreator() }
        Divider()
        Button("Rename Space…") { beginRename(project) }
        Button("Change Icon…") { beginIconChange(project) }
        Divider()
        Button("Remove Space…", role: .destructive) { manager.close(project) }
    }

    private func beginRename(_ project: Project) {
        projectBeingRenamed = project
        renameDraft = project.name
    }

    private func commitRename() {
        let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        projectBeingRenamed?.customName = name
        projectBeingRenamed = nil
    }

    private func beginRename(_ tab: PaneTab) {
        tabBeingRenamed = tab
        tabRenameDraft = tab.displayTitle ?? ""
    }

    private func commitTabRename() {
        let name = tabRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        tabBeingRenamed?.customName = name
        tabBeingRenamed = nil
    }

    private func beginIconChange(_ project: Project) {
        projectChangingIcon = project
        iconDraft = project.customIcon ?? ""
    }

    private func commitIcon(_ icon: String?) {
        projectChangingIcon?.customIcon = icon
        projectChangingIcon = nil
    }

    private func setPinned(_ pinned: Bool, tab: PaneTab, project: Project) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
            project.setPinned(pinned, tabID: tab.id)
        }
    }

    private func updateTabDrag(source: UUID, location: CGPoint, project: Project) {
        draggedTabID = source
        NSCursor.closedHand.set()
        let target = tabFrames.first(where: {
            $0.key != source && $0.value.contains(location)
        })?.key

        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
            if let target {
                project.moveTab(source, to: target)
            } else {
                project.setPinned(location.y < temporarySectionY, tabID: source)
            }
        }
    }

    private func endTabDrag() {
        draggedTabID = nil
        NSCursor.arrow.set()
    }

    private var adjacentProject: Project? {
        adjacentProject(for: swipeOffset)
    }

    private func adjacentOffset(for sidebarWidth: CGFloat) -> CGFloat {
        swipeOffset < 0
            ? sidebarWidth + swipeOffset
            : -sidebarWidth + swipeOffset
    }

    private func updateSpaceSwipe(_ translation: CGFloat) {
        guard !reduceMotion else { return }
        let hasDestination = adjacentProject(for: translation) != nil
        swipeOffset = hasDestination
            ? max(-CGFloat(width), min(CGFloat(width), translation))
            : rubberBand(translation, dimension: CGFloat(width))
    }

    private func finishSpaceSwipe(_ translation: CGFloat, velocity: CGFloat) {
        guard let destination = adjacentProject(for: translation) else {
            settleSpaceSwipe()
            return
        }
        let projected = translation + velocity * 0.12
        guard abs(projected) >= CGFloat(width) * 0.28 else {
            settleSpaceSwipe()
            return
        }

        if reduceMotion {
            manager.selectedProjectID = destination.id
            swipeOffset = 0
            return
        }

        let incomingOffset = translation < 0
            ? CGFloat(width) + swipeOffset
            : -CGFloat(width) + swipeOffset
        manager.selectedProjectID = destination.id
        swipeOffset = incomingOffset
        settleSpaceSwipe()
    }

    private func adjacentProject(for translation: CGFloat) -> Project? {
        guard translation != 0,
              manager.projects.count > 1,
              let current = manager.projects.firstIndex(where: {
                  $0.id == manager.selectedProjectID
              })
        else { return nil }
        let delta = translation < 0 ? 1 : -1
        let index = (current + delta + manager.projects.count) % manager.projects.count
        return manager.projects[index]
    }

    private func settleSpaceSwipe() {
        swipeOffset = 0
    }

    private func rubberBand(_ offset: CGFloat, dimension: CGFloat) -> CGFloat {
        let magnitude = abs(offset)
        let resisted = magnitude * dimension * 0.55
            / (dimension + 0.55 * magnitude)
        return offset < 0 ? -resisted : resisted
    }

}

private struct SidebarTabRow: View {
    @ObservedObject var tab: PaneTab
    @ObservedObject private var themeChanges = Theme.changes
    let agentKind: AgentKind?
    let agentState: AgentDisplayState?
    let isSelected: Bool
    let fontSize: Double
    let select: () -> Void
    let close: () -> Void

    @State private var isHovering = false

    private var displayTitle: String {
        if let customName = tab.customName, !customName.isEmpty {
            return customName
        }
        if case .session(let session)? = tab.focusedContent {
            let folder = URL(
                fileURLWithPath: session.currentDirectoryPath,
                isDirectory: true
            ).lastPathComponent
            return folder.isEmpty ? "/" : folder
        }
        return tab.displayTitle ?? "Untitled"
    }

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                SidebarTabIcon(
                    tab: tab, agentKind: agentKind,
                    agentState: agentState, isSelected: isSelected
                )

                Text(displayTitle)
                    .font(.system(size: fontSize))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if tab.allPanes.count > 1 {
                    Text("\(tab.allPanes.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }

                if isHovering {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                } else if tab.focusedContent?.isDirty == true {
                    Circle()
                        .fill(.secondary)
                        .frame(width: 5, height: 5)
                        .frame(width: 16, height: 16)
                        .accessibilityLabel("Unsaved changes")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected
                        ? Color.primary.opacity(0.09)
                        : (isHovering ? Color.primary.opacity(0.04) : .clear)
                )
        }
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

}

private struct SidebarTabIcon: View {
    @ObservedObject var tab: PaneTab
    let agentKind: AgentKind?
    let agentState: AgentDisplayState?
    let isSelected: Bool

    private var foregroundStyle: AnyShapeStyle {
        if let agentState { return AnyShapeStyle(agentState.color) }
        return isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }

    @ViewBuilder
    var body: some View {
        Group {
            if let agentKind, let agentState {
                Image(systemName: agentState.systemImage)
                    .help("\(agentKind.displayName) · \(agentState.label)")
                    .accessibilityLabel("\(agentKind.displayName) agent, \(agentState.label)")
            } else if case .browser(let browser)? = tab.focusedContent {
                BrowserFaviconView(browser: browser, size: 14)
            } else {
                Image(systemName: tab.focusedContent?.systemImage ?? "square")
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(foregroundStyle)
        .frame(width: 14, height: 14)
    }
}

extension AgentDisplayState {
    var color: Color {
        switch self {
        case .blocked: return .orange
        case .working: return .green
        case .done: return .teal
        case .idle, .unknown: return .secondary
        }
    }
}

struct ChromeIconButton: View {
    let systemImage: String
    let tooltip: String
    var font: Font = .system(size: 12, weight: .medium)
    var iconSize: CGFloat = 16
    var tooltipEdge: TooltipEdge = .below
    var tooltipAlignment: HorizontalAlignment = .trailing
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(font)
                .foregroundStyle(isHovering ? .primary : .secondary)
                .frame(width: iconSize, height: iconSize)
                .padding(4)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color.primary.opacity(0.08) : .clear)
                }
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .tooltip(tooltip, edge: tooltipEdge, alignment: tooltipAlignment)
    }
}

private struct SidebarFooterButton: View {
    let systemImage: String
    let tooltip: String
    var tooltipAlignment: HorizontalAlignment = .leading
    let action: () -> Void

    var body: some View {
        ChromeIconButton(
            systemImage: systemImage,
            tooltip: tooltip,
            tooltipEdge: .above,
            tooltipAlignment: tooltipAlignment,
            action: action
        )
    }
}

private struct SidebarTabFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct SidebarTemporarySectionPreferenceKey: PreferenceKey {
    static let defaultValue = CGFloat.infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

/// Watches precise horizontal trackpad scrolling only while the pointer is
/// over the sidebar. Content panes keep their own horizontal gesture semantics.
private struct SpaceSwipeMonitor: NSViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> SpaceSwipeMonitorView {
        let view = SpaceSwipeMonitorView()
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateNSView(_ view: SpaceSwipeMonitorView, context: Context) {
        view.onChanged = onChanged
        view.onEnded = onEnded
    }
}

@MainActor
private final class SpaceSwipeMonitorView: NSView {
    var onChanged: ((CGFloat) -> Void)?
    var onEnded: ((CGFloat, CGFloat) -> Void)?

    private var eventMonitor: Any?
    private var translation: CGFloat = 0
    private var velocity: CGFloat = 0
    private var lastTimestamp: TimeInterval?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        guard let window else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
            [weak self, weak window] event in
            let input = SpaceSwipeEvent(event)
            let output: SpaceSwipeEvent = assumeMainActor {
                guard let self, let window, window.isKeyWindow,
                      let event = input.value,
                      event.hasPreciseScrollingDeltas,
                      event.window === window
                else { return input }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return input }
                self.handle(event)
                return input
            }
            return output.value
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        let horizontal = event.scrollingDeltaX
        guard abs(horizontal) > abs(event.scrollingDeltaY)
                || event.phase == .ended
                || event.phase == .cancelled
        else { return }

        if event.phase == .began || event.phase == .mayBegin {
            translation = 0
            velocity = 0
            lastTimestamp = event.timestamp
        }
        if horizontal != 0 {
            if let lastTimestamp {
                let elapsed = event.timestamp - lastTimestamp
                if elapsed > 0 { velocity = horizontal / elapsed }
            }
            lastTimestamp = event.timestamp
            translation += horizontal
            onChanged?(translation)
        }

        if event.phase == .ended || event.phase == .cancelled {
            let finalTranslation = translation
            let finalVelocity = velocity
            translation = 0
            velocity = 0
            lastTimestamp = nil
            onEnded?(finalTranslation, finalVelocity)
        }
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}

private struct SpaceSwipeEvent: @unchecked Sendable {
    let value: NSEvent?

    init(_ value: NSEvent?) {
        self.value = value
    }
}
