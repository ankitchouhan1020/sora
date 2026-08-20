#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

log="$temporary/states"
cat > "$temporary/sora" <<'EOF'
#!/bin/sh
printf '%s\n' "$3" >> "$SORA_TEST_LOG"
EOF
chmod +x "$temporary/sora"
export SORA_BIN_PATH="$temporary/sora"
export SORA_TERMINAL_ID=00000000-0000-0000-0000-000000000000
export SORA_TEST_LOG="$log"

node --input-type=module - "$root/Sora/AgentIntegrations/opencode/sora-agent-state.js" <<'EOF'
const { SoraAgentStatePlugin } = await import(process.argv[2]);
const plugin = await SoraAgentStatePlugin();
await plugin["chat.message"]();
await plugin.event({ event: { type: "question.asked" } });
await plugin.event({ event: { type: "session.idle" } });
EOF
printf 'working\nblocked\nidle\n' | cmp - "$log"

grok="$root/Sora/AgentIntegrations/grok/sora-agent-state.grok.json"
python3 -m json.tool "$grok" >/dev/null
grep -q 'agent state working' "$grok"
grep -q 'agent state idle' "$grok"
grep -q 'agent state blocked' "$grok"
printf 'Agent integration checks passed.\n'
