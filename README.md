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
- Space-scoped tab, pane, and agent automation through the bundled `sora` CLI

## CLI

```sh
sora space list
sora space create --name "Ship auth" --repository ~/Code/app
sora space select <space-id>
sora space rename <space-id> "Review auth"
sora space remove <space-id> --force
sora tab create --pinned --name worker
sora pane split --right
sora pane run --pane <pane-id> -- npm test
sora agent start worker --kind pi --pane <pane-id>
sora agent prompt worker --text "Run the focused tests" --wait
sora agent read worker --lines 120
sora agent install <pi|opencode|grok|all>
```

Tab, pane, and agent commands stay inside the invoking terminal's Space. Agent
launches use structured arguments, while prompts go directly to the running
agent instead of through a shell. Pi, OpenCode, and Grok integrations report
trusted working, blocked, and idle lifecycle states; Sora never infers state
from rendered terminal text.

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
