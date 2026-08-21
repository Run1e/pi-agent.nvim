import { Meta } from "./dispatcher";
import { registerTools } from "./tools";

export type PiCommands = {
  init: { enabled_tools: string[] };
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

export type NvimCommands = {
  nvim_get_qflist: null;
  nvim_set_qflist: {
    entries: {
      file: string;
      lnum: number;
      col: number;
      special_command?: string;
    }[];
  };
};

export type NvimCommandResults = {
  nvim_get_qflist: string[];
  nvim_set_qflist: number;
};

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
  meta.ctx.ui.notify("[simple-pi] text appended to prompt");
};

export const handlePing: CommandHandler<"ping"> = (meta, data) => {
  meta.sendEvent("pong", {});
};

export const handleTest: CommandHandler<"test"> = async (meta, data) => {
  const result = await meta.invokeCommand("testcommand", {
    hello: "there",
  });

  meta.ctx.ui.notify(result.ret);
};

export const handleInit: CommandHandler<"init"> = (meta, data) => {
  registerTools(meta.pi, meta.dispatcher, data.enabled_tools);

  let initMsg = "Connected to Neovim :D";

  if (data.enabled_tools.length) {
    initMsg += ` Enabled tools: ${data.enabled_tools.join(", ")}`;
  } else {
    initMsg += " No tools enabled!";
  }

  meta.ctx.ui.notify(initMsg);
};
