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
import { listenRegisterEventInterest } from "./events.ts";

export type SendDataFn = (data: Message) => void;

export type Message = {
  correlation_id: number;
  type: "command" | "event";
  name: string;
  data: any;
};

export type PersistentData = {
  registeredListeners: string[];
  blockingListeners: Map<string, boolean>;
};

let client: Socket | null = null;
let dispatcher: Dispatcher | null = null;

let persistentData: PersistentData = {
  registeredListeners: [],
  blockingListeners: new Map(),
};

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
    getContext().ui.notify("[pi-agent] Connected to Neovim :D"),
  );

  client.on("end", () => {
    getContext().ui.notify("[pi-agent] Lost connection to Neovim D:", "error");
  });

  client.on("error", (err) => {
    getContext().ui.notify("[pi-agent] " + err.message, "error");
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
      const sendData: SendDataFn = (data: Message) => {
        if (!client || client.destroyed || client.closed) {
          throw new Error("Connection to Neovim closed, unable to send data");
        }

        client.write(JSON.stringify(data) + "\n");
      };

      dispatcher = new Dispatcher(pi, ctx, sendData, persistentData);

      // register command handlers
      dispatcher.setHandler("append_text", handleAppendText);
      dispatcher.setHandler("ping", handlePing);
      dispatcher.setHandler("test", handleTest);
      dispatcher.setHandler("init", handleInit);

      dispatcher.addListener(
        "register_event_interest",
        listenRegisterEventInterest,
      );
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
