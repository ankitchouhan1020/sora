# Sora

A native terminal workspace for macOS.

![preview](https://sora.ankitchouhan.dev/sora-screenshot.png)

## Features

- Swift + libghostty by default, with an optional Alacritty backend
- Native design
- Split panes
- Git intergration
- Organize work into Spaces
- File tree
- Project-scoped pane and Space automation through the bundled `sora` CLI and MCP server

## CLI

```sh
sora space list
sora space create --name "Ship auth" --repository ~/Code/app
sora space select <space-id>
sora space rename <space-id> "Review auth"
sora run --space <space-id> -- npm test
sora space remove <space-id> --force
sora pane split --right
sora pane send --pane <pane-id> --text "npm test" --submit
sora pane wait --pane <pane-id> --contains "passed"
sora agent install <pi|opencode|grok|all>
```

Pane commands stay inside the invoking terminal's project. Pi, OpenCode, and Grok integrations report trusted working, blocked, and idle lifecycle states; other detected agents remain Unknown.

The same Space and pane operations are available through `sora mcp` when it runs inside a Sora terminal.

## Download

https://sora.ankitchouhan.dev

Or with Homebrew:

```sh
brew install ankitchouhan1020/tap/sora
```

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md)

## License

GPLv3
