import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import type { Protocol, Command } from "./handlers.ts";
import { handlers } from "./handlers.ts";

import { createConnection, Socket } from "net";

export default function (pi: ExtensionAPI) {
  let client: Socket;

  // React to events
  pi.on("session_start", async (_event, ctx) => {
    // ctx.ui.setEditorText("hello :D");

    function onConnect() {
      ctx.ui.notify("Connected to Neovim! :D");
    }

    const sessionIdIdx = process.argv.findIndex(
      (value) => value === "--session-id",
    );

    if (sessionIdIdx == -1) {
      ctx.ui.notify(
        "Failed to find session name set from Neovim, exiting",
        "error",
      );

      return;
    }

    const sessionName = process.argv[sessionIdIdx + 1];

    client = createConnection({ path: "/tmp/" + sessionName }, onConnect);

    client.on("end", () => {
      ctx.ui.notify("Lost connection to Neovim! D:", "error");
    });

    client.on("error", (err) => {
      ctx.ui.notify(err.message, "error");
      client.destroy();
    });

    function dispatch<K extends keyof Protocol>(command: Command<K>) {
      const handler = handlers[command.command];
      if (handler == undefined) {
        return;
      }

      handler(pi, ctx, buildReplier(command.id), command.data);
    }

    function buildReplier(id: number) {
      return (eventName: string, data: object) => {
        client.write(
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

    let buffer = "";

    client.on("data", (chunk: Buffer) => {
      buffer += chunk.toString("utf8");

      let nl: number;
      while ((nl = buffer.indexOf("\n")) !== -1) {
        const line = buffer.slice(0, nl);
        buffer = buffer.slice(nl + 1);
        if (line.length > 0) {
          const msg: unknown = JSON.parse(line);
          handleMessage(msg);
        }
      }
    });
  });
}
