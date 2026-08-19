import {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

import { CommandHandler, PiCommand, PiCommands } from "./commands";
import { EventListener, PiEvent, PiEvents } from "./events";

export type Meta = {
  pi: ExtensionAPI;
  ctx: ExtensionContext;
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
  private sendData: (data: object) => void;
  private nextId = 100;

  constructor(
    pi: ExtensionAPI,
    ctx: ExtensionContext,
    sendData: (data: object) => void,
  ) {
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

  buildMeta(correlationId: number): Meta {
    const invokeCommand = (name: string, data: any) => {
      const newCorrelationId = correlationId;

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
          reject("Timed out waiting for command");
        }, 1000);

        successUnsubscribe = this.addListener("success", (data) => {
          if (data.correlation_id !== newCorrelationId) return;
          resolve(data.value);
        });

        failureUnsubscribe = this.addListener("failure", (data) => {
          if (data.correlation_id !== newCorrelationId) return;
          reject("failure");
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
      });
    };

    const sendEvent = (name: string, data: any) => {
      // events are fire-and-forget
      this.sendData({
        type: "event",
        name: name,
        correlation_id: this.newCorrelationId(),
        data: data,
      });
    };

    return {
      pi: this.pi,
      ctx: this.ctx,
      invokeCommand: invokeCommand,
      sendEvent: sendEvent,
    };
  }

  async handleCommand<K extends keyof PiCommands>(command: PiCommand<K>) {
    const handler = this.handlers.get(command.name);
    if (handler == undefined) {
      return;
    }

    let value;

    try {
      value = await handler(
        this.buildMeta(command.correlation_id),
        command.data,
      );
    } catch (e: any) {
      this.sendData({
        type: "event",
        name: "failure",
        correlation_id: command.correlation_id,
        data: { correlation_id: command.correlation_id, message: e.message },
      });
      return;
    }

    this.sendData({
      type: "event",
      name: "success",
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
        // TODO: some kind of logging?
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
      // TODO: maybe print the error or something lol
      this.handleCommand(msg).catch((_) => {});
    } else if (this.isEvent(msg)) {
      this.handleEvent(msg);
    }
  }
}
