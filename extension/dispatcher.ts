import {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

import { CommandHandler, PiCommand, PiCommands } from "./commands";
import { EventListener } from "./events";
import { SendDataFn } from "./pi-agent";
import {
  NvimCommandResults,
  NvimCommands,
  NvimEvent,
  NvimEvents,
} from "./extern";

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

  private pi: ExtensionAPI;
  private ctx: ExtensionContext;
  private sendData: SendDataFn;
  private nextId = 100;

  public eventData: EventData = {
    registeredListeners: new Set(),
    blockingListeners: new Map(),
  };

  constructor(pi: ExtensionAPI, ctx: ExtensionContext, sendData: SendDataFn) {
    this.pi = pi;
    this.ctx = ctx;
    this.sendData = sendData;
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

  getContext(): ExtensionContext {
    return this.ctx;
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

  sendEvent(name: string, data: any): number {
    const correlationId = this.newCorrelationId();

    // events are fire-and-forget
    this.sendData({
      type: "event",
      name: name,
      correlation_id: correlationId,
      data: data,
    });

    return correlationId;
  }

  buildMeta(): Meta {
    return {
      pi: this.pi,
      ctx: this.ctx,
      dispatcher: this,
    };
  }

  async handleCommand<K extends keyof PiCommands>(command: PiCommand<K>) {
    let value;

    try {
      const handler = this.handlers.get(command.name);
      if (handler == undefined) {
        throw new Error(`Unknown command: ${command.name}`);
      }

      value = await handler(this.buildMeta(), command.data);
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
    const listeners = this.listeners.get(event.name) ?? [];
    const meta = this.buildMeta();

    for (const listener of listeners) {
      try {
        listener(meta, event.data);
      } catch (e: any) {
        this.ctx.ui.notify(
          `Event listener for event '${event.name}' threw: ${e?.message ?? String(e)}`,
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
          `Command handler for command '${msg.name}' threw: ${e?.message ?? String(e)}`,
        );
      });
    } else if (this.isEvent(msg)) {
      this.handleEvent(msg);
    }
  }
}
