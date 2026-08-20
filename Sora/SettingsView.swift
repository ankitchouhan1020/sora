//
//  SettingsView.swift
//  sora
//

import AppKit
import GhosttyTheme
import SwiftUI

/// The app settings window (Cmd+,).
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var themeChanges = Theme.changes

    @State private var selectedPane: SettingsPane = .general

    /// Installed fixed-pitch families (bundled default first).
    private let families = TerminalFont.selectableFamilies()

    private let sidebarWidth: CGFloat = 224
    private let paneWidth: CGFloat = 650

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selectedPane)
                .frame(width: sidebarWidth)

            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(width: 0.5)

            currentPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 900, height: 700)
        .background(SettingsBackdrop())
        .tint(SettingsPalette.accent)
    }

    @ViewBuilder
    private var currentPane: some View {
        switch selectedPane {
        case .general: generalPane
        case .appearance: appearancePane
        case .terminal: terminalPane
        case .editor: editorPane
        case .automation: automationPane
        case .updates: updatesPane
        }
    }

    private func settingsPane<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPaneHeader(pane: selectedPane)
                content()
            }
            .frame(maxWidth: paneWidth, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .background(SettingsPalette.content)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsSectionCard(title: title, detail: detail, content: content)
    }

    private var generalPane: some View {
        settingsPane {
            settingsSection("Workspace", detail: "The defaults Sora applies to every project window.") {
                settingRow(
                    "Sidebar text",
                    detail: "Project names, file rows, git status, and Beads stay readable at a glance."
                ) {
                    sizeControl(
                        "Sidebar text size",
                        value: $settings.sidebarFontSize,
                        range: AppSettings.sidebarFontSizeRange
                    )
                }

                SettingsDivider()

                settingRow(
                    "Settings file",
                    detail: "A local TOML file you can inspect, back up, or sync yourself.",
                    controlWidth: 268
                ) {
                    ConfigPathBadge(text: configPathDisplay, help: AppSettings.configURL.path)
                }
            }

            settingsSection("Reset", detail: "Return this Mac to Sora’s recommended defaults.") {
                settingRow(
                    "Restore defaults",
                    detail: "Clears local preferences without touching projects, sessions, or files."
                ) {
                    Button("Restore Defaults", role: .destructive) { settings.resetToDefaults() }
                        .disabled(resetDisabled)
                        .controlSize(.regular)
                        .accessibilityHint("Restores local Sora preferences without changing projects or files.")
                }
            }
        }
    }

    private var appearancePane: some View {
        settingsPane {
            settingsSection("Appearance mode", detail: "Follow macOS automatically or pin Sora to one look.") {
                ThemePicker(selection: $settings.theme)
                    .padding(10)
            }

            settingsSection("Color themes", detail: "Pick separate palettes for light and dark work.") {
                settingRow("Dark palette", detail: "Used at night or whenever Sora is in dark appearance.") {
                    Picker("Dark palette", selection: $settings.themeDark) {
                        ForEach(Self.darkThemeNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Dark palette")
                }

                SettingsDivider()

                settingRow("Light palette", detail: "Used for bright desktops and system light mode.") {
                    Picker("Light palette", selection: $settings.themeLight) {
                        ForEach(Self.lightThemeNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Light palette")
                }

                sectionNote("Theme changes update terminals, editor surfaces, sidebars, and window chrome together.")
            }

            settingsSection("Typography", detail: "One code font across terminals, editor, diffs, and previews.") {
                settingRow("Font family", detail: "Bundled JetBrains Mono is tuned for prompts, glyphs, and dense output.") {
                    Picker("Font family", selection: $settings.fontFamily) {
                        Text("\(TerminalFont.bundledFamily) (Bundled)").tag("")
                        Divider()
                        ForEach(families.dropFirst(), id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Font family")
                }

                SettingsDivider()

                settingRow("Text size", detail: "Applies immediately to new code surfaces and live previews.") {
                    sizeControl("Text size", value: $settings.fontSize, range: AppSettings.fontSizeRange)
                }

                TerminalSampleBlock(font: previewFont, thicken: settings.fontThicken)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }
        }
    }

    private var terminalPane: some View {
        settingsPane {
            if TerminalBackend.selectable.count > 1 {
                settingsSection(
                    "Terminal engine",
                    detail: "Choose the renderer new panes use. Existing panes keep their current engine."
                ) {
                    TerminalBackendPicker(selection: $settings.terminalBackend)
                        .padding(10)
                }
            }

            settingsSection("Shell behavior", detail: "Input and scrollback choices for long-running terminal work.") {
                settingToggle(
                    "Thicker text",
                    detail: "Adds a little weight when terminal output feels too faint on your display.",
                    isOn: $settings.fontThicken
                )

                SettingsDivider()

                settingToggle(
                    "Option as Meta",
                    detail: "Sends Option-key chords to shells, editors, and terminal apps.",
                    isOn: $settings.macosOptionAsAlt
                )

                SettingsDivider()

                settingToggle(
                    "Restore scrollback",
                    detail: "Reopens recent output above a fresh shell when Sora launches again.",
                    isOn: $settings.restoreTerminalHistory
                )
            }
        }
    }

    private var editorPane: some View {
        settingsPane {
            settingsSection("Editor behavior", detail: "Small defaults that keep file editing predictable.") {
                settingToggle(
                    "Wrap long lines",
                    detail: "Keeps wide files readable inside the editor instead of forcing horizontal scrolling.",
                    isOn: $settings.wrapLines
                )

                EditorSampleBlock(wrapLines: settings.wrapLines, font: previewFont)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                sectionNote("Typography is controlled in Appearance so terminals, editor, previews, and diffs stay in sync.")
            }
        }
    }

    private var automationPane: some View {
        settingsPane {
            settingsSection("Local automation", detail: "Controlled helper access for the projects you can see.") {
                settingToggle(
                    "Allow helpers",
                    detail: "Lets Sora’s CLI coordinate Spaces, tabs, panes, and agents on this Mac.",
                    isOn: $settings.allowLocalAutomation
                )

                sectionNote("Local only. No network service is opened; turning this off immediately blocks helper control.")
            }

            settingsSection("Beads", detail: "Find project issues without making every project configure paths.") {
                settingRow(
                    "bd executable",
                    detail: settings.beadsExecutable.isEmpty
                        ? "Auto-discovery checks Homebrew and PATH before asking you."
                        : "Sora will use this exact Beads CLI for project panels.",
                    controlWidth: 268
                ) {
                    TextField("Auto-discover bd", text: $settings.beadsExecutable)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .accessibilityLabel("bd executable path")
                        .accessibilityHint("Leave empty to let Sora discover bd automatically.")
                }

                SettingsDivider()

                settingRow(
                    "Resolution",
                    detail: "Only set a custom path when auto-discovery cannot find bd.",
                    controlWidth: 268
                ) {
                    Text(settings.beadsExecutable.isEmpty ? "Automatic discovery" : "Custom executable path")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SettingsPalette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                sectionNote("Sora runs bd locally inside the selected project; no issue data leaves your Mac.")
            }
        }
    }

    private var updatesPane: some View {
        settingsPane {
            settingsSection("Sora", detail: "A native macOS workspace for terminals, files, diffs, git, and agents.") {
                AboutCard(version: appVersion, build: appBuild)
                    .padding(12)
            }

            settingsSection("Updates", detail: "Stay current with signed Sora releases.") {
                settingToggle(
                    "Automatic checks",
                    detail: "Sora quietly checks for signed updates in the background.",
                    isOn: $updater.automaticallyChecksForUpdates
                )

                SettingsDivider()

                settingRow("Check now", detail: "Open the update checker when you want to verify manually.") {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                        .controlSize(.regular)
                        .accessibilityHint("Opens the update checker.")
                }
            }
        }
    }

    private var configPathDisplay: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return AppSettings.configURL.path.replacingOccurrences(of: home, with: "~")
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development"
    }

    private var appBuild: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    private func settingToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        settingRow(title, detail: detail, controlWidth: 72) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
                .accessibilityHint(detail)
        }
    }

    private func settingRow<Control: View>(
        _ title: String,
        detail: String,
        controlWidth: CGFloat = 250,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(SettingsPalette.primaryText)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondaryText)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control()
                .frame(width: controlWidth, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func sectionNote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(SettingsPalette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 11)
    }

    private func sizeControl(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Slider(value: value, in: range, step: 1)
                .accessibilityLabel(label)
            Text("\(Int(value.wrappedValue)) pt")
                .font(.caption.monospacedDigit())
                .foregroundStyle(SettingsPalette.secondaryText)
                .frame(width: 44, alignment: .trailing)
                .accessibilityHidden(true)
            Stepper(label, value: value, in: range, step: 1)
                .labelsHidden()
                .frame(width: 20)
                .accessibilityLabel(label)
        }
    }

    private var resetDisabled: Bool {
        settings.fontFamily.isEmpty
            && settings.fontSize == AppSettings.defaultFontSize
            && settings.sidebarFontSize == AppSettings.defaultSidebarFontSize
            && !settings.fontThicken
            && !settings.macosOptionAsAlt
            && settings.theme == .system
            && settings.themeDark == Theme.defaultDarkThemeName
            && settings.themeLight == Theme.defaultLightThemeName
            && !settings.wrapLines
            && !settings.restoreTerminalHistory
            && settings.beadsExecutable.isEmpty
            && settings.allowLocalAutomation
            && settings.terminalBackend == .fallback
    }

    private var previewFont: NSFont {
        TerminalFont.resolve(family: settings.fontFamily, size: CGFloat(settings.fontSize))
    }

    /// The compact catalog of popular themes shared by both terminal backends,
    /// split by the appearance slot they suit.
    private static let darkThemeNames = Theme.commonDarkThemes.map(\.name)
    private static let lightThemeNames = Theme.commonLightThemes.map(\.name)
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case appearance
    case terminal
    case editor
    case automation
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .terminal: "Terminal"
        case .editor: "Editor"
        case .automation: "Advanced"
        case .updates: "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Set the defaults that make every project window feel right."
        case .appearance: "Tune the look of terminals, editor surfaces, and Sora chrome."
        case .terminal: "Choose the renderer and keyboard behavior for new shell panes."
        case .editor: "Keep file editing predictable across source and diff views."
        case .automation: "Control local helpers and project issue discovery."
        case .updates: "Check version details and keep Sora current."
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .terminal: "terminal"
        case .editor: "doc.text"
        case .automation: "slider.horizontal.3"
        case .updates: "info.circle"
        }
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .general: "1"
        case .appearance: "2"
        case .terminal: "3"
        case .editor: "4"
        case .automation: "5"
        case .updates: "6"
        }
    }

    var shortcutLabel: String {
        switch self {
        case .general: "1"
        case .appearance: "2"
        case .terminal: "3"
        case .editor: "4"
        case .automation: "5"
        case .updates: "6"
        }
    }
}

private struct SettingsBackdrop: View {
    var body: some View {
        SettingsPalette.content
            .ignoresSafeArea()
    }
}

private enum SettingsPalette {
    static var content: Color { Color(nsColor: Theme.background) }
    static var sidebar: Color { Color(nsColor: Theme.sidebar) }
    static var foreground: Color { primaryText }
    static var primaryText: Color { Color(nsColor: textColor(level: .primary)) }
    static var secondaryText: Color { Color(nsColor: textColor(level: .secondary)) }
    static var tertiaryText: Color { Color(nsColor: textColor(level: .tertiary)) }
    static var accent: Color { Color(nsColor: Theme.accent) }
    static var divider: Color { Color(nsColor: Theme.divider) }

    static var card: Color { Color(nsColor: surface(elevation: 0.07)) }
    static var cardHover: Color { Color(nsColor: surface(elevation: 0.12)) }

    private enum TextLevel { case primary, secondary, tertiary }

    private static func textColor(level: TextLevel) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let theme = Theme.terminal(dark: isDark)
            let background = theme.backgroundNSColor
            let foreground = theme.foregroundNSColor
            let candidate: NSColor = switch level {
            case .primary:
                foreground
            case .secondary:
                background.blended(withFraction: 0.88, of: foreground) ?? foreground
            case .tertiary:
                background.blended(withFraction: 0.78, of: foreground) ?? foreground
            }
            return candidate.contrastRatio(on: background) >= 7 ? candidate : foreground
        }
    }

    private static func surface(elevation: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return Theme.terminal(dark: isDark).surfaceNSColor(elevation: elevation)
        }
    }
}

private struct SettingsPaneHeader: View {
    let pane: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(SettingsPalette.accent.opacity(0.16))
                    Image(systemName: pane.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SettingsPalette.accent)
                }
                .frame(width: 30, height: 30)

                Text(pane.title)
                    .font(.title3.weight(.semibold))
                    .tracking(-0.2)
                    .accessibilityAddTraits(.isHeader)
            }

            Text(pane.subtitle)
                .font(.callout)
                .foregroundStyle(SettingsPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    let detail: String?
    let content: Content

    init(
        title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SettingsPalette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondaryText)
                        .lineSpacing(1)
                }
            }
            .padding(.horizontal, 3)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(SettingsPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.primary.opacity(0.095), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 5)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.leading, 12)
    }
}

private struct ConfigPathBadge: View {
    let text: String
    let help: String

    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .foregroundStyle(SettingsPalette.secondaryText)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(
                Capsule(style: .continuous)
                    .fill(.quaternary.opacity(0.7))
            )
            .help(help)
            .accessibilityLabel("Settings file path")
            .accessibilityValue(help)
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane
    @FocusState private var focusedPane: SettingsPane?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: { selection = .general }) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .shadow(color: .black.opacity(0.20), radius: 8, y: 3)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sora")
                            .font(.callout.weight(.semibold))
                        Text("Local workspace")
                            .font(.caption)
                            .foregroundStyle(SettingsPalette.secondaryText)
                    }

                    Spacer(minLength: 0)
                }
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.075))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sora local workspace")
            .accessibilityHint("Shows General settings.")
            .padding(.horizontal, 12)
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsPane.allCases) { pane in
                    SettingsSidebarRow(
                        pane: pane,
                        isSelected: selection == pane,
                        isFocused: focusedPane == pane,
                        select: { selection = pane }
                    )
                    .focused($focusedPane, equals: pane)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsPalette.sidebar)
        .onAppear { focusedPane = selection }
        .onChange(of: selection) { focusedPane = $0 }
        .onChange(of: focusedPane) { if let pane = $0 { selection = pane } }
        .onMoveCommand { direction in
            switch direction {
            case .up: moveSelection(-1)
            case .down: moveSelection(1)
            default: break
            }
        }
    }

    private func moveSelection(_ step: Int) {
        let panes = SettingsPane.allCases
        guard let index = panes.firstIndex(of: selection) else { return }
        selection = panes[(index + step + panes.count) % panes.count]
    }
}

private struct SettingsSidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    let isFocused: Bool
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(iconFill)
                    Image(systemName: pane.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(width: 24, height: 24)

                Text(pane.title)
                    .font(.callout.weight(isSelected ? .semibold : .medium))

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? SettingsPalette.primaryText : SettingsPalette.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .overlay {
                if isFocused && !isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(SettingsPalette.accent.opacity(0.85), lineWidth: 1.5)
                }
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(SettingsPalette.accent)
                        .frame(width: 3, height: 18)
                        .padding(.leading, 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(pane.shortcutKey, modifiers: .command)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(pane.title) settings")
        .accessibilityHint("Opens the \(pane.title) settings pane. Command \(pane.shortcutLabel).")
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var iconFill: Color {
        isSelected ? SettingsPalette.accent.opacity(0.20) : SettingsPalette.divider.opacity(hovering ? 1.0 : 0.65)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? SettingsPalette.cardHover : SettingsPalette.divider.opacity(hovering ? 0.7 : 0))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.primary.opacity(isSelected ? 0.08 : 0), lineWidth: 0.5)
            )
    }
}

private struct TerminalSampleBlock: View {
    let font: NSFont
    let thicken: Bool

    var body: some View {
        FontThickenSample(
            font: font,
            thicken: thicken,
            foreground: Theme.terminal(dark: true).foregroundNSColor
        )
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: Theme.terminal(dark: true).backgroundNSColor))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("sora, ~/dev/sora, git status --short. Modified SettingsView.swift. 2 panes, Beads ready, editor synced.")
    }
}

private struct FontThickenSample: NSViewRepresentable {
    let font: NSFont
    let thicken: Bool
    let foreground: NSColor

    func makeNSView(context: Context) -> FontThickenSampleView {
        FontThickenSampleView()
    }

    func updateNSView(_ view: FontThickenSampleView, context: Context) {
        view.font = font
        view.thicken = thicken
        view.foreground = foreground
        view.invalidateIntrinsicContentSize()
        view.needsDisplay = true
    }
}

private final class FontThickenSampleView: NSView {
    var font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    var thicken = false
    var foreground = NSColor.textColor

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: ceil(font.boundingRectForFont.height) * 3 + 12)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setAllowsFontSmoothing(true)
        context.setShouldSmoothFonts(thicken)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        let secondary = foreground.withAlphaComponent(0.65)
        let lines: [NSAttributedString] = [
            joined([
                ("sora", NSColor.systemGreen),
                ("   ~/dev/sora", secondary),
                ("   git status --short", foreground),
            ]),
            joined([(" M sora/SettingsView.swift", NSColor.systemOrange)]),
            joined([("2 panes · Beads ready · editor synced", secondary)]),
        ]
        var y: CGFloat = 0
        let lineHeight = ceil(font.boundingRectForFont.height) + 6
        for line in lines {
            line.draw(at: NSPoint(x: 0, y: y))
            y += lineHeight
        }
    }

    private func joined(_ parts: [(String, NSColor)]) -> NSAttributedString {
        let line = NSMutableAttributedString()
        for (text, color) in parts {
            line.append(NSAttributedString(
                string: text,
                attributes: [.font: font, .foregroundColor: color]
            ))
        }
        return line
    }
}

private struct EditorSampleBlock: View {
    let wrapLines: Bool
    let font: NSFont

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("SettingsView.swift")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SettingsPalette.secondaryText)
                Spacer(minLength: 0)
                Text(wrapLines ? "Wrapped" : "Single line")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SettingsPalette.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule(style: .continuous).fill(.quaternary.opacity(0.7)))
            }
            Text("if status.hasChanges(in: selectedProject) { showDiffPreview(for: file, preservingScrollPosition: true) }")
                .font(Font(font))
                .lineLimit(wrapLines ? 2 : 1)
                .truncationMode(.tail)
            Text(wrapLines ? "Soft wrapping enabled" : "Horizontal scrolling")
                .font(.caption)
                .foregroundStyle(SettingsPalette.secondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct AboutCard: View {
    let version: String
    let build: String?

    private var versionLine: String {
        if let build, !build.isEmpty { return "Version \(version) (\(build))" }
        return "Version \(version)"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Sora")
                    .font(.title3.weight(.semibold))
                Text(versionLine)
                    .font(.callout)
                    .foregroundStyle(SettingsPalette.secondaryText)
                Text("Native macOS terminal workspace")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondaryText)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct ThemePicker: View {
    @Binding var selection: AppTheme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AppTheme.allCases) { theme in
                ThemeOption(
                    theme: theme,
                    isSelected: selection == theme,
                    select: { selection = theme }
                )
            }
        }
    }
}

private struct ThemeOption: View {
    let theme: AppTheme
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 7) {
                ThemePreview(theme: theme)
                HStack(spacing: 5) {
                    Text(theme.title)
                        .font(.callout.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? SettingsPalette.primaryText : SettingsPalette.secondaryText)
                        .lineLimit(1)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(SettingsPalette.accent)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? SettingsPalette.accent.opacity(0.14) : SettingsPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isSelected ? SettingsPalette.accent : SettingsPalette.divider, lineWidth: isSelected ? 1.5 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.title) appearance")
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityHint("Sets the Settings and app appearance mode.")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Keeps every available engine visible, following the same selection model
/// as the Appearance tabs above while leaving room for capability differences.
private struct TerminalBackendPicker: View {
    @Binding var selection: TerminalBackend

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(TerminalBackend.selectable) { backend in
                TerminalBackendOption(
                    backend: backend,
                    isSelected: selection == backend,
                    select: { selection = backend }
                )
            }
        }
    }
}

private struct TerminalBackendOption: View {
    let backend: TerminalBackend
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(backend.settingsIconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(backend.displayName)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(SettingsPalette.primaryText)
                        Text(backend.settingsBadge)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(SettingsPalette.secondaryText)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isSelected ? SettingsPalette.accent : SettingsPalette.secondaryText)
                }

                Text(backend.settingsSummary)
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(backend.settingsBullets, id: \.self) { bullet in
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(SettingsPalette.accent)
                            Text(bullet)
                                .lineLimit(1)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(SettingsPalette.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(minHeight: 120, alignment: .topLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? SettingsPalette.accent.opacity(0.12) : SettingsPalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        isSelected ? SettingsPalette.accent : SettingsPalette.divider,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(backend.displayName) terminal engine")
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityHint(backend.settingsSummary)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private extension TerminalBackend {
    var settingsSummary: String {
        switch self {
        case .libghostty:
            "Sora’s default terminal engine, tuned for compatibility."
        case .alacritty:
            "A lean Metal renderer using Alacritty’s terminal core."
        }
    }

    var settingsBadge: String {
        switch self {
        case .libghostty:
            "Recommended"
        case .alacritty:
            "Lean core"
        }
    }

    var settingsBullets: [String] {
        switch self {
        case .libghostty:
            ["Recommended default", "Images and shell integration"]
        case .alacritty:
            ["Lower memory use", "Fast grid renderer"]
        }
    }
}

/// A miniature sora window painted in one appearance's real colors. `system`
/// splits down the middle — light on the left, dark on the right — the same
/// way System Settings previews "Auto".
private struct ThemePreview: View {
    let theme: AppTheme

    private static let size = CGSize(width: 112, height: 58)
    private static let corner: CGFloat = 8

    var body: some View {
        ZStack {
            switch theme {
            case .light:
                MiniWindow(dark: false)
            case .dark:
                MiniWindow(dark: true)
            case .system:
                MiniWindow(dark: false)
                MiniWindow(dark: true)
                    .mask(alignment: .trailing) {
                        Rectangle().frame(width: Self.size.width / 2)
                    }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.corner))
        .overlay(
            RoundedRectangle(cornerRadius: Self.corner)
                .strokeBorder(.primary.opacity(0.15), lineWidth: 0.5)
        )
    }
}

/// Sidebar, traffic lights, a tab, and a few lines of terminal output —
/// enough of sora's layout to read at thumbnail size.
private struct MiniWindow: View {
    let dark: Bool

    var body: some View {
        let theme = Theme.terminal(dark: dark)
        let text = Color(nsColor: theme.foregroundNSColor)
        let cursor = Color(nsColor: theme.cursorNSColor)

        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 2.5) {
                    dot(0xFF5F57)
                    dot(0xFEBC2E)
                    dot(0x28C840)
                }
                .padding(.bottom, 4)

                bar(14, text.opacity(0.35))
                bar(10, text.opacity(0.35))
                bar(14, text.opacity(0.35))
            }
            .padding(6)
            .frame(minWidth: 30, maxWidth: 30, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: Theme.sidebarFill(dark: dark)))

            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(text.opacity(0.12))
                    .frame(width: 18, height: 6)
                    .padding(.bottom, 1)

                HStack(spacing: 2) {
                    bar(3, cursor)
                    bar(32, text.opacity(0.8))
                }
                bar(44, text.opacity(0.45))
                bar(24, text.opacity(0.45))
                HStack(spacing: 2) {
                    bar(3, cursor)
                    bar(11, text.opacity(0.8))
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: theme.backgroundNSColor))
        }
    }

    private func dot(_ hex: Int) -> some View {
        Circle()
            .fill(Color(
                .sRGB,
                red: Double((hex >> 16) & 0xff) / 255,
                green: Double((hex >> 8) & 0xff) / 255,
                blue: Double(hex & 0xff) / 255
            ))
            .frame(width: 4, height: 4)
    }

    private func bar(_ width: CGFloat, _ fill: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.2)
            .fill(fill)
            .frame(width: width, height: 3)
    }
}

private extension NSColor {
    func contrastRatio(on background: NSColor) -> CGFloat {
        let lighter = max(relativeLuminance, background.relativeLuminance)
        let darker = min(relativeLuminance, background.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var relativeLuminance: CGFloat {
        let color = usingColorSpace(.sRGB) ?? self
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.redComponent)
            + 0.7152 * channel(color.greenComponent)
            + 0.0722 * channel(color.blueComponent)
    }
}

#Preview {
    SettingsView()
}
