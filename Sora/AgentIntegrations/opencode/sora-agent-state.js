// Managed by Sora's explicit integration installer.
// SORA_INTEGRATION_ID=opencode
// SORA_INTEGRATION_VERSION=1
import { execFile } from "node:child_process";

const bin = process.env.SORA_BIN_PATH;
const terminalID = process.env.SORA_TERMINAL_ID;
let lastState;
let reports = Promise.resolve();

const enabled = () => !!bin && !!terminalID;
const report = (state) => {
  if (!enabled() || state === lastState) return reports;
  lastState = state;
  reports = reports.then(() => new Promise((resolve) => {
    execFile(bin, ["agent", "state", state], { timeout: 2000 }, resolve);
  }));
  return reports;
};

const stateFromStatus = (status) => {
  const value = typeof status === "string" ? status : status?.type;
  switch (value?.toLowerCase()) {
    case "idle": return "idle";
    case "active":
    case "busy":
    case "pending":
    case "retry":
    case "running":
    case "streaming":
    case "working": return "working";
    default: return undefined;
  }
};

export const SoraAgentStatePlugin = async () => {
  if (!enabled()) return {};
  return {
    "chat.message": async () => report("working"),
    event: async ({ event }) => {
      const type = event?.type;
      const properties = event?.properties ?? {};
      switch (type) {
        case "session.status": {
          const state = stateFromStatus(properties.status);
          if (state) await report(state);
          break;
        }
        case "tool.execute.before":
        case "tool.execute.after":
        case "permission.replied":
        case "question.replied":
        case "question.rejected":
        case "session.compacted":
          await report("working");
          break;
        case "permission.asked":
        case "question.asked":
        case "session.error":
          await report("blocked");
          break;
        case "session.idle":
          await report("idle");
          break;
        default:
          break;
      }
    },
  };
};
