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
- Local automation through the bundled `sora` CLI and MCP server, including Space creation, selection, renaming, removal, and terminal spawning

## CLI

```sh
sora space list
sora space create --name "Ship auth" --repository ~/Code/app
sora space select <space-id>
sora space rename <space-id> "Review auth"
sora run --space <space-id> -- npm test
sora space remove <space-id> --force
sora agent install pi
```

The Pi integration reports working, needs-input, and idle lifecycle states to Sora; other detected agents remain Unknown until they have a trusted integration.

The same Space operations are available through `sora mcp`.

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
