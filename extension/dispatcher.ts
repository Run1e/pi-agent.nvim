import {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

import { CommandHandler, PiCommand, PiCommands } from "./commands";
import { EventListener } from "./events";
import {
  NvimCommandResults,
  NvimCommands,
  NvimEvent,
  NvimEvents,
} from "./extern";
import { createConnection, Socket } from "net";
import { findSocket } from "./utils";
import { existsSync } from "fs";

type Message = {
  correlation_id: number;
  type: "command" | "event";
  name: string;
  data: any;
};

export type EventData = {
  registeredListeners: Set<string>;
  blockingListeners: Map<string, boolean>;
};

export type Meta = {
  pi: ExtensionAPI;
  ctx: ExtensionContext;
  dispatcher: Dispatcher;
};

export class Dispatcher {
  private handlers = new Map<
    keyof PiCommands,
    CommandHandler<keyof PiCommands>
  >();

  private listeners = new Map<
    keyof NvimEvents,
    EventListener<keyof NvimEvents>[]
  >();

  private meta: Meta;
  private pi: ExtensionAPI;
  private ctx: ExtensionContext;
  private client: Socket | null;
  private socketPath: string;
  private nextId = 100;
  private reconnectTimer: NodeJS.Timeout | null;

  public eventData: EventData = {
    registeredListeners: new Set(),
    blockingListeners: new Map(),
  };

  constructor(pi: ExtensionAPI, ctx: ExtensionContext) {
    this.pi = pi;
    this.ctx = ctx;

    this.socketPath = findSocket();
    this.client = this.ensureClient();

    this.reconnectTimer = null;

    this.meta = {
      pi: pi,
      ctx: ctx,
      dispatcher: this,
    };
  }

  updateContext(ctx: ExtensionContext) {
    this.ctx = ctx;
    this.meta.ctx = ctx;
  }

  isReady(): boolean {
    return this.client != null && !this.client.destroyed && !this.client.closed;
  }

  onDisconnect() {
    // we've disconnected, remove the client from the instance and use the client
    // passed into this function when handling reconnect
    if (this.client == null) {
      return;
    }

    this.client.destroy();
    this.client = null;

    this.reconnectTimer = setTimeout(() => {
      this.ctx.ui.notify("[pi-agent] attempting reconnect");

      this.reconnectTimer = null;

      if (!existsSync(this.socketPath)) {
        this.ctx.ui.notify(
          "[pi-agent] socket file deleted, not attempting more reconnects",
        );
        return;
      }

      const client = this.ensureClient();
      if (client != null && this.client == null) {
        this.client = client;
      }
    }, 500);
  }

  ensureClient(): Socket | null {
    // do nothing if we have a good client
    if (this.isReady()) {
      return null;
    }

    const client = createConnection({ path: this.socketPath }, () => {
      if (this.reconnectTimer != null) {
        clearTimeout(this.reconnectTimer);
      }
    });

    // other side signaled end of transmission
    client.on("end", () => {
      if (this.client == client) {
        this.onDisconnect();
      }
    });

    // socket fully closed
    client.on("close", () => {
      if (this.client == client) {
        this.onDisconnect();
      }
    });

    // an error occurred, 'close' will be called directly afterwards
    client.on("error", (err) => {
      this.ctx.ui.notify(
        `[pi-agent] socket error: ${err?.message ?? String(err)}`,
      );
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

          this.dispatch(msg);
        }
      }
    });

    return client;
  }

  sendData(data: Message) {
    if (!this.isReady()) {
      return;
    }

    // lsp complains but this shouldn't be null because the guard above
    this.client?.write(JSON.stringify(data) + "\n");
  }

  setHandler<K extends keyof PiCommands>(name: K, handler: CommandHandler<K>) {
    this.handlers.set(name, handler as CommandHandler<keyof PiCommands>);
  }

  addListener<K extends keyof NvimEvents>(name: K, listener: EventListener<K>) {
    let arr = this.listeners.get(name);

    if (arr === undefined) {
      arr = [];
      this.listeners.set(name, arr);
    }

    arr.push(listener as EventListener<keyof NvimEvents>);

    return () => {
      const current = this.listeners.get(name);
      if (current !== undefined) {
        const idx = current.indexOf(
          listener as EventListener<keyof NvimEvents>,
        );
        if (idx !== -1) {
          current.splice(idx, 1);
        }
        if (current.length === 0) {
          this.listeners.delete(name);
        }
      }
    };
  }

  newCorrelationId() {
    const nextId = this.nextId;
    this.nextId += 1;
    return nextId;
  }

  async waitForEvent<K extends keyof NvimEvents>(
    name: K,
    predicate: (event: NvimEvents[K]) => boolean,
    timeout: number = 2500,
  ): Promise<NvimEvents[K]> {
    let timeoutId: NodeJS.Timeout;
    let unsubscribe: () => void;

    return new Promise((resolve, reject) => {
      if (timeout != 0) {
        timeoutId = setTimeout(() => {
          reject(new Error(`timed out in waitForEvent '${name}'`));
        }, timeout);
      }

      unsubscribe = this.addListener(name, (_, data: NvimEvents[K]) => {
        if (predicate(data)) {
          resolve(data);
        }
      });
    }).finally(() => {
      try {
        unsubscribe();
      } catch (e) {
        //
      }

      if (timeoutId != null) {
        clearTimeout(timeoutId);
      }
    }) as Promise<NvimEvents[K]>;
  }

  async sendCommand<K extends keyof NvimCommands>(
    name: K,
    data: NvimCommands[K],
  ): Promise<NvimCommandResults[K]> {
    if (!this.isReady()) {
      throw new Error("Not connected to Neovim");
    }

    const correlationId = this.newCorrelationId();

    this.sendData({
      type: "command",
      name: name,
      correlation_id: correlationId,
      data: data,
    });

    return Promise.race([
      this.waitForEvent(
        "command_success",
        (data) => data.correlation_id === correlationId,
      ),
      this.waitForEvent(
        "command_failure",
        (data) => data.correlation_id === correlationId,
      ).then((data) => {
        throw new Error(data.error);
      }),
    ]).then((data) => data.value);
  }

  sendEvent(name: string, data: any) {
    if (!this.isReady()) {
      return;
    }

    // events are fire-and-forget
    this.sendData({
      type: "event",
      name: name,
      correlation_id: this.newCorrelationId(),
      data: data,
    });
  }

  async handleCommand<K extends keyof PiCommands>(command: PiCommand<K>) {
    if (!this.isReady()) {
      return;
    }

    let value;

    try {
      const handler = this.handlers.get(command.name);
      if (handler == undefined) {
        throw new Error(`Unknown command: ${command.name}`);
      }

      value = await handler(this.meta, command.data);
    } catch (e: any) {
      this.sendData({
        type: "event",
        name: "command_failure",
        correlation_id: command.correlation_id,
        data: {
          correlation_id: command.correlation_id,
          error: e?.message ?? String(e),
        },
      });
      return;
    }

    this.sendData({
      type: "event",
      name: "command_success",
      correlation_id: command.correlation_id,
      data: { correlation_id: command.correlation_id, value: value },
    });
  }

  handleEvent<K extends keyof NvimEvents>(event: NvimEvent<K>) {
    if (!this.isReady()) {
      return;
    }

    const listeners = this.listeners.get(event.name) ?? [];

    for (const listener of listeners) {
      try {
        listener(this.meta, event.data);
      } catch (e: any) {
        this.ctx.ui.notify(
          `[pi-agent] listener for event '${event.name}' threw: ${e?.message ?? String(e)}`,
        );
        continue;
      }
    }
  }

  isCommand(msg: unknown): msg is PiCommand {
    return (
      msg != null &&
      typeof msg == "object" &&
      "type" in msg &&
      msg.type === "command"
    );
  }

  isEvent(msg: unknown): msg is NvimEvent {
    return (
      msg != null &&
      typeof msg == "object" &&
      "type" in msg &&
      msg.type === "event"
    );
  }

  dispatch(msg: unknown) {
    if (this.isCommand(msg)) {
      this.handleCommand(msg).catch((e) => {
        this.ctx.ui.notify(
          `handler for command '${msg.name}' threw: ${e?.message ?? String(e)}`,
        );
      });
    } else if (this.isEvent(msg)) {
      this.handleEvent(msg);
    }
  }
}
