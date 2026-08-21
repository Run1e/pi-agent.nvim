import {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

import {
  CommandHandler,
  NvimCommandResults,
  NvimCommands,
  PiCommand,
  PiCommands,
} from "./commands";
import { EventListener, PiEvent, PiEvents } from "./events";
import { SendDataFn } from "./simple-pi";

export type Meta = {
  pi: ExtensionAPI;
  ctx: ExtensionContext;
  dispatcher: Dispatcher;
  invokeCommand: (name: string, data: any) => Promise<any>;
  sendEvent: (name: string, data: any) => void;
};

export class Dispatcher {
  private handlers = new Map<
    keyof PiCommands,
    CommandHandler<keyof PiCommands>
  >();

  private listeners = new Map<
    keyof PiEvents,
    EventListener<keyof PiEvents>[]
  >();

  private pi: ExtensionAPI;
  private ctx: ExtensionContext;
  private sendData: SendDataFn;
  private nextId = 100;

  constructor(pi: ExtensionAPI, ctx: ExtensionContext, sendData: SendDataFn) {
    this.pi = pi;
    this.ctx = ctx;
    this.sendData = sendData;
  }

  setHandler<K extends keyof PiCommands>(name: K, handler: CommandHandler<K>) {
    this.handlers.set(name, handler as CommandHandler<keyof PiCommands>);
  }

  addListener<K extends keyof PiEvents>(name: K, listener: EventListener<K>) {
    let arr = this.listeners.get(name);

    if (arr === undefined) {
      arr = [];
      this.listeners.set(name, arr);
    }

    arr.push(listener as EventListener<keyof PiEvents>);

    return () => {
      const current = this.listeners.get(name);
      if (current !== undefined) {
        const idx = current.indexOf(listener as EventListener<keyof PiEvents>);
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

  sendCommand<K extends keyof NvimCommands>(
    name: K,
    data: NvimCommands[K],
  ): Promise<NvimCommandResults[K]> {
    const newCorrelationId = this.newCorrelationId();

    this.sendData({
      type: "command",
      name: name,
      correlation_id: newCorrelationId,
      data: data,
    });

    let successUnsubscribe: () => void;
    let failureUnsubscribe: () => void;
    let timeoutId: NodeJS.Timeout;

    return new Promise((resolve, reject) => {
      timeoutId = setTimeout(() => {
        reject(new Error(`command '${name}' timed out`));
      }, 2500);

      successUnsubscribe = this.addListener("command_success", (data) => {
        if (data.correlation_id !== newCorrelationId) return;
        resolve(data.value as NvimCommandResults[K]);
      });

      failureUnsubscribe = this.addListener("command_failure", (data) => {
        if (data.correlation_id !== newCorrelationId) return;
        reject(new Error(data.error));
      });
    }).finally(() => {
      try {
        successUnsubscribe();
      } catch (e) {}
      try {
        failureUnsubscribe();
      } catch (e) {}

      if (timeoutId != null) {
        clearTimeout(timeoutId);
      }
    }) as Promise<NvimCommandResults[K]>;
  }

  sendEvent(name: string, data: any) {
    // events are fire-and-forget
    this.sendData({
      type: "event",
      name: name,
      correlation_id: this.newCorrelationId(),
      data: data,
    });
  }

  buildMeta(): Meta {
    return {
      pi: this.pi,
      ctx: this.ctx,
      dispatcher: this,
      invokeCommand: this.sendCommand,
      sendEvent: this.sendEvent,
    };
  }

  async handleCommand<K extends keyof PiCommands>(command: PiCommand<K>) {
    const handler = this.handlers.get(command.name);
    if (handler == undefined) {
      return;
    }

    let value;

    try {
      value = await handler(this.buildMeta(), command.data);
    } catch (e: any) {
      this.sendData({
        type: "event",
        name: "command_failure",
        correlation_id: command.correlation_id,
        data: { correlation_id: command.correlation_id, error: e.message },
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

  handleEvent<K extends keyof PiEvents>(event: PiEvent<K>) {
    const listeners = this.listeners.get(event.name) ?? [];

    for (const listener of listeners) {
      try {
        listener(event.data);
      } catch (e: any) {
        this.ctx.ui.notify(
          `Event listener for event '${event.name}' threw: ${e.message}`,
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

  isEvent(msg: unknown): msg is PiEvent {
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
          `Command handler for command '${msg.name}' threw: ${e.message}`,
        );
      });
    } else if (this.isEvent(msg)) {
      this.handleEvent(msg);
    }
  }
}
