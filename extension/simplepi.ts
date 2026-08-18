import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

import type { Protocol, Command } from "./handlers.ts";
import { handlers } from "./handlers.ts";

import { createConnection, Socket } from "net";

let client: Socket | null = null;
let _pi: ExtensionAPI | null = null;
let _ctx: ExtensionContext | null = null;

function getSessionName(): string {
  const sessionIdIdx = process.argv.findIndex(
    (value) => value === "--session-id",
  );

  if (sessionIdIdx == -1) {
    throw new Error("(simplepi) Couldn't find session name");
  }

  return process.argv[sessionIdIdx + 1];
}

function getClient(): Socket {
  if (!client || client.destroyed) {
    throw new Error();
  }

  return client;
}

function getContext(): ExtensionContext {
  if (!_ctx) {
    throw new Error();
  }

  return _ctx;
}

function getPi(): ExtensionAPI {
  if (!_pi) {
    throw new Error();
  }

  return _pi;
}

function createClient() {
  client = createConnection({ path: "/tmp/" + getSessionName() }, () =>
    getContext().ui.notify("Connected to Neovim! :D"),
  );

  client.on("end", () => {
    getContext().ui.notify("Lost connection to Neovim! D:", "error");
  });

  client.on("error", (err) => {
    getContext().ui.notify(err.message, "error");
    getClient().destroy();
  });

  let buffer = "";

  client.on("data", (chunk: Buffer) => {
    buffer += chunk.toString("utf8");

    let nl: number;
    while ((nl = buffer.indexOf("\n")) !== -1) {
      const line = buffer.slice(0, nl);
      buffer = buffer.slice(nl + 1);
      if (line.length > 0) {
        let msg: unknown;
        try {
          msg = JSON.parse(line);
        } catch (e) {
          continue;
        }

        handleMessage(msg);
      }
    }
  });
}

function dispatch<K extends keyof Protocol>(command: Command<K>) {
  const handler = handlers[command.command];
  if (handler == undefined) {
    return;
  }

  handler(getPi(), getContext(), buildReplier(command.id), command.data);
}

function buildReplier(id: number) {
  return (eventName: string, data: object) => {
    getClient().write(
      JSON.stringify({ id: id, event: eventName, data: data }) + "\n",
    );
  };
}

function isCommand(msg: unknown): msg is Command {
  return (
    msg != null &&
    typeof msg == "object" &&
    "command" in msg &&
    typeof msg.command == "string" &&
    msg.command in handlers &&
    "data" in msg &&
    typeof msg.data == "object"
  );
}

function handleMessage(msg: unknown) {
  if (!isCommand(msg)) {
    return;
  }

  dispatch(msg);
}

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async (_event, ctx) => {
    _pi = pi;
    _ctx = ctx;

    if (!client || client.destroyed) {
      createClient();
    }
  });
}
