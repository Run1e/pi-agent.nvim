import { Meta } from "./dispatcher";
import { listenRegisterEventInterest } from "./events";
import { registerTools } from "./tools";

export type PiCommands = {
  init: {
    enabled_tools: string[];
    events: string[];
    events_blocking: string[];
  };
  append_text: { lines: string[]; as_paragraph: boolean };
  ping: {};
  test: {};
};

export type PiCommand<K extends keyof PiCommands = keyof PiCommands> = {
  [Key in K]: { correlation_id: number; name: Key; data: PiCommands[Key] };
}[K];

export type CommandHandler<K extends keyof PiCommands> = (
  meta: Meta,
  data: PiCommands[K],
) => any;

export const handleAppendText: CommandHandler<"append_text"> = (meta, data) => {
  // TODO: possible to insert where the users' cursor is?
  // there's "pasteToEditor" but that doesn't let us do spacing particularly well...
  let oldText = meta.ctx.ui.getEditorText();
  const joined = data.lines.join("\n");

  let newText = "";

  if (data.as_paragraph) {
    oldText = oldText.replace(/\n+$/, "");
    if (!oldText.length) {
      newText = joined;
    } else {
      newText = `${oldText}\n\n${joined}\n\n`;
    }
  } else {
    if (!oldText.length) {
      newText = joined;
    } else if (oldText.endsWith(" ") || oldText.endsWith("\n")) {
      newText = oldText + joined;
    } else {
      newText = oldText + " " + joined;
    }

    if (!newText.endsWith(" ")) {
      newText += " ";
    }
  }

  meta.ctx.ui.setEditorText(newText);

  // I don't really like this,
  // but it forces a repaint which doesn't happen with setEditorText for some reason.
  meta.ctx.ui.notify("[pi-agent] text appended to prompt");
};

export const handlePing: CommandHandler<"ping"> = (meta, data) => {
  meta.dispatcher.sendEvent("pong", {});
};

export const handleTest: CommandHandler<"test"> = async (meta, data) => {
  const result = await meta.dispatcher.sendCommand("test_command", {
    hello: "there",
  });

  meta.ctx.ui.notify(result.ret);
};

export const handleInit: CommandHandler<"init"> = (meta, data) => {
  registerTools(meta.pi, meta.dispatcher, data.enabled_tools);

  for (const event_name of data.events) {
    listenRegisterEventInterest(meta, {
      event_name: event_name,
      blocking: false,
    });
  }

  for (const event_name of data.events_blocking) {
    listenRegisterEventInterest(meta, {
      event_name: event_name,
      blocking: true,
    });
  }

  meta.ctx.ui.notify("Connected to Neovim :D");
};
