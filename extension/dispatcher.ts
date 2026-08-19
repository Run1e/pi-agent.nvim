import {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

import { CommandHandler, PiCommand, PiCommands } from "./commands";
import { EventListener, PiEvent, PiEvents } from "./events";

export type Meta = {
  pi: ExtensionAPI;
  ctx: ExtensionContext;
  invokeCommand: (name: string, data: object) => void;
  sendEvent: (name: string, data: object) => void;
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
  }

  getContext(): ExtensionContext {
    return this.ctx;
  }

  buildMeta(correlationId: number): Meta {
    return {
      pi: this.pi,
      ctx: this.ctx,
      invokeCommand: (name, data) => {
        this.sendData({
          type: "command",
          name: name,
          correlationId: correlationId,
          data: data,
        });
        // TODO: check for ack
      },
      sendEvent: (name, data) => {
        this.sendData({
          type: "event",
          name: name,
          correlationId: correlationId,
          data: data,
        });
      },
    };
  }

  handleCommand<K extends keyof PiCommands>(command: PiCommand<K>) {
    const handler = this.handlers.get(command.name);
    if (handler == undefined) {
      return;
    }

    try {
      handler(this.buildMeta(command.correlationId), command.data);
    } catch (e: any) {
      this.sendData({
        type: "event",
        name: "failure",
        correlationId: command.correlationId,
        data: { correlationId: command.correlationId, message: e.message },
      });
      return;
    }

    this.sendData({
      type: "event",
      name: "success",
      correlationId: command.correlationId,
      data: { correlationId: command.correlationId },
    });
  }

  // handleEvent<K extends keyof PiEvents>(event: PiEvent<K>) {
  //   const listeners =
  // }

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
      this.handleCommand(msg);
    } else if (this.isEvent(msg)) {
    }
  }
}
