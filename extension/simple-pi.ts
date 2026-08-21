import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

import { Dispatcher } from "./dispatcher.ts";

import { createConnection, Socket } from "net";
import {
  handleAppendText,
  handleInit,
  handlePing,
  handleTest,
} from "./commands.ts";
import { findSocket } from "./utils.ts";
import { registerTools } from "./tools.ts";

let client: Socket | null = null;
let dispatcher: Dispatcher | null = null;

function getClient(): Socket {
  if (!client || client.destroyed) {
    throw new Error("No valid client running");
  }

  return client;
}

function getContext(): ExtensionContext {
  if (!dispatcher) {
    throw new Error("No dispatcher, can't provide context");
  }

  return dispatcher.getContext();
}

function createClient() {
  client = createConnection({ path: findSocket() }, () =>
    getContext().ui.notify("[simple-pi] Connected to Neovim :D"),
  );

  client.on("end", () => {
    getContext().ui.notify("[simple-pi] Lost connection to Neovim D:", "error");
  });

  client.on("error", (err) => {
    getContext().ui.notify("[simple-pi] " + err.message, "error");
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

        if (dispatcher) {
          dispatcher.dispatch(msg);
        }
      }
    }
  });
}

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async (event, ctx) => {
    if (!client || client.destroyed || client.closed) {
      createClient();
    }

    if (!dispatcher) {
      const sendData = (data: object) => {
        if (!client || client.destroyed || client.closed) {
          throw new Error("Connection to Neovim closed, unable to send data");
        }

        client.write(JSON.stringify(data) + "\n");
      };

      dispatcher = new Dispatcher(pi, ctx, sendData);

      // register command handlers
      dispatcher.setHandler("append_text", handleAppendText);
      dispatcher.setHandler("ping", handlePing);
      dispatcher.setHandler("test", handleTest);
      dispatcher.setHandler("init", handleInit);
    }
  });

  pi.on("session_shutdown", async (event, ctx) => {
    if (event.reason === "quit") return;

    if (client) {
      client.destroy();
    }

    if (dispatcher) {
      dispatcher = null;
    }
  });
}
