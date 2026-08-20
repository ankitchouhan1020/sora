# Changelog

All notable changes to Sora. This file is the **source of truth for the release
notes shown in the in-app updater**: [`scripts/release.ts`](scripts/release.ts)
extracts the section whose heading matches the version being released
(`MARKETING_VERSION`) and publishes it next to the update, so Sparkle shows it in
the update prompt.

Format follows [Keep a Changelog](https://keepachangelog.com). Add a new
`## [<version>]` section at the top for each release, matching the version you
set in the Xcode project.

Write release notes for the final product users receive, not the development
history. When a feature is still unreleased, fold its fixes and refinements into
the original feature bullet instead of adding separate entries for them.

## [unrelease]

## [0.5.0]

- Let coding agents coordinate Space-scoped pinned tabs and panes through Sora’s CLI, with readable direct prompts and trusted Pi, OpenCode, and Grok lifecycle reporting.
- Pin and unpin tabs reliably by dragging them between sidebar sections, even when a section is empty.

## [0.4.0]

- See working, blocked, completed, idle, and unknown coding-agent states across Spaces, and jump directly to agents from Search.
- Switch rapidly between busy Spaces without terminal stalls, stale tab selection, or runaway background work.

## [0.3.0]

- Organize work in Spaces with vertical pinned and temporary tabs, attached repositories, custom icons, and trackpad switching.
- Rename tabs directly from the left sidebar.
- Collapse every expanded folder in the file viewer with one click.
- The `sora` CLI and MCP server now manage Spaces directly, including creating, selecting, renaming, removing, and opening terminals within them.

## [0.2.3]

- Command-click terminal links to reveal local files in Finder, or open files and websites directly in new Sora tabs and panes.
- Terminal notifications now sound reliably, work from Alacritty sessions, and return you to the session that sent them when clicked.
- Alacritty terminals now handle modified keys, Shift-Enter multiline prompts, application keypads, and app-controlled pointer shapes correctly.
- Switch directly to tabs with Ctrl+1–9, without also holding Shift.
- New sessions start in the project's pinned directory, and browser tabs work with sites that require a modern Safari identity.
- Prevent rare Ctrl-Tab crashes and runaway Git metadata checks outside repositories.

## [0.2.2]

- Files, Git, and Beads now follow coding agents into separate checkouts, clearly label worktrees, and show Git change badges beside files and folders.
- Ctrl-Tab now switches by recent use, selected grouped tabs stay visible as the window changes, and command-palette keyboard and pointer selection stay predictable.
- Grok sessions now join Sora's Agents tab group, and the typography preview reflects the Thicker text setting.

## [0.2.1]

- Sidebar headers now align with macOS window controls.
- Command-running terminals now stay in the Terminals tab group instead of splitting into a separate Commands group.
- Terminals no longer inject the legacy Kero CLI token; use the bundled `sora` helper for local automation.
- Settings now use a custom macOS surface with a fixed sidebar, compact pane headers, and aligned setting cards.

## [0.2.0]

- Settings now use a cleaner sidebar layout with grouped macOS panes
- Tab group headers now offer bulk close actions, including closing all files and inactive terminals, without the extra selected-group checkmark
- Prevent terminal tabs from crashing after switching sessions or resizing during a partial redraw
- Files created in a terminal now use your system's default permissions instead of being made private to your user
- Terminal sessions now inherit your shell locale instead of Sora setting `LANG`
- CJK monospace fonts now appear in the terminal font picker
- Open native browser tabs and split panes from the command palette or terminal/editor context menus, with a combined address/search field, navigation controls, page sharing, and restored URLs

## [0.1.32]

- The left sidebar toggle remains available in the title bar after hiding the sidebar

## [0.1.31]

- File previews now refresh after files are changed outside Sora
- Option-key characters from macOS input sources such as Polish Pro now work in terminals; users who prefer terminal Meta bindings can opt in under Settings → Terminal

## [0.1.30]

- Fix Chinese IME under the Alacritty backend
- Reduce hidden Ghostty tab renderer memory
- Opening the Ctrl-Tab switcher no longer highlights whichever tab happens under the stationary pointer
- Sessions you never open no longer cost any GPU memory. Reopening a window used to draw restored sessions straight away, holding full-size buffers you looked at or not; now a pane claims one only when you first view it.

## [0.1.29]

- Add project-scoped Beads panel for reviewing, filtering, claiming, closing, reopening, and handing agent tasks back to the terminal
- The Git panel now refreshes after commands and when Sora regains focus instead of polling continuously in the background

## [0.1.28]

- Group tabs into calm, connected Agents, Files, Commands, and Terminals sections that collapse without disrupting tab navigation or reordering
- Enable the bundled `sora` CLI MCP server by default; local automation can still be switched off in Settings
- Refresh Sora website local automation details and deploy it through the maintainer-owned Cloudflare Worker
- Tweak some UI colors

## [0.1.27]

- Add opt-in local automation through the bundled `sora` CLI and MCP server for opening projects and controlling visible terminal tabs — without opening a network port
- Choose which terminal emulator drives new panes in Settings → Terminal → Backend. Ghostty remains the default, with a new Alacritty backend
- Configure the left and right sidebar font size in Settings

## [0.1.26]

- Processes list no longer shows `<defunct>` entries: those are exited children waiting to be reaped, not something you can see output from or kill
- Opening a large diff no longer freezes the window: diffs render only the rows on screen and highlight them off the main thread
- The font setting now applies to the diff viewer too, so diffs match the terminal and editor

## [0.1.25]

- Add a tab switcher (ctrl-tab) to switch between tabs
- Add audio input support for CLIs that might need it

## [0.1.24]

- set TERM_PROGRAM to ghostty to get image rendering support

## [0.1.23]

- Fix pasting clipboard images into image-aware TUIs such as Grok, and paste Finder-copied files as shell-safe absolute paths (#20)

## [0.1.22]

- Add “Open in Sora” to Finder’s folder context menu, opening each selected folder as a project with its terminal started there
- Full-screen programs with their own background color (vim, htop, TUIs) now fill the terminal pane: the padding around the grid takes on the adjacent content's background instead of always showing the theme background, leaving only a hairline frame at the pane edges
- Fix non-ASCII rendering in git diff view
- Allow to rename session tabs

## [0.1.21]

- Anchor the file tree and Git panel to the project directory — the closest git repository containing the terminal's directory — so they no longer re-root every time you `cd` inside a repo; outside a repository they keep following the terminal as before
- Add "Set Project Directory…" to the project's context menu to pin a fixed directory for these panels ("Use Automatic Directory" reverts); the pin is remembered across relaunches
- Info panel: the Directory section is now split into Current Directory (the shell's live cwd, shown when it differs) and Project Directory, marked "(AUTO)" while derived automatically, with a "?" popover explaining both modes
- Remember sidebar layout across relaunches: each window restores whether the left and right sidebars were open and which right panel (Files/Git/Info) was selected

## [0.1.20]

- Security: stop terminal programs from silently reading your clipboard — an OSC 52 escape sequence (for example from a remote SSH host) could previously read the macOS clipboard without any prompt; Sora now asks for confirmation first, matching the Ghostty app default (#8)
- Warn before pasting text that looks like it could execute commands, matching Ghostty's paste protection
- Add color themes: Settings → Colors picks a theme per appearance — Sora's Default Light/Dark plus all 485 bundled Ghostty themes — recoloring the terminal, window chrome, sidebars, and editor live. The built-in Defaults keep the GitHub palette and translucent sidebar; every other theme colors the sidebar too
- Fix fuzzy-looking terminal text: font thickening was unintentionally always on, making glyphs heavier and softer than stock Ghostty
- Add a "Thicken font strokes" toggle in Settings → Font for those who prefer the heavier rendering

## [0.1.19]

- Fix a releasing signing issue

## [0.1.18]

- Fix max height of settings window

## [0.1.17]

- Add pane zoom: ⇧⌘↩ toggles the focused pane filling the tab, with a header button indicating the state and exiting zoom
- Add shortcuts to cycle pane focus (⌘[ / ⌘]), resize panes (⌃⌘ arrows) and equalize panes (⌃⌘=)

## [0.1.16]

- Tweaks shortcut description for toggling right sidebar

## [0.1.15]

- Fix potential memory leak

## [0.1.14]

- Add theme setting to force light or dark theme

## [0.1.13]

- Make editor full height
- Tweaks sidebar

## [0.1.12]

- Fix TSX highlight

## [0.1.10]

- fix git panel

## [0.1.9]

- Fix CPU usage spike due to libghostty intergration bug

## [0.1.8]

- Use libghostty

## [0.1.7]

- Remove GPU rendering temporarily

## [0.1.6]

- Fix window maximizing
- Shortcut for left sidebar: cmd-b

## [0.1.5]

- Double-click the title bar to zoom the window (honors the system "double-click a window's title bar to" setting)
- fix gpu rendering

## [0.1.4]

- Add "Session Contents Restored" divider to restored terminals
- set TERM_PROGRAM to Sora
- fix embedded language highlighting in markdown

## [0.1]

### Added
- Initial release.
