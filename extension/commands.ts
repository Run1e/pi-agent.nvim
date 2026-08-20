import { Meta } from "./dispatcher";
import { registerTools } from "./tools";

export type PiCommands = {
  init: { enabled_tools: string[] };
  append_text: { lines: string[]; as_paragraph: boolean };
  ping: {};
  test: {};
};

export type PiCommand<K extends keyof PiCommands = keyof PiCommands> = {
  [K2 in K]: { correlation_id: number; name: K2; data: PiCommands[K2] };
}[K];

export type CommandHandler<K extends keyof PiCommands> = (
  meta: Meta,
  data: PiCommands[K],
) => any | Promise<any>;

export const handleAppendText: CommandHandler<"append_text"> = (meta, data) => {
  // TODO: possible to insert where the users' cursor is?
  // there's "pasteToEditor" but that doesn't let us do spacing particularly well...
  const oldText = meta.ctx.ui.getEditorText();
  const joined = data.lines.join("\n");

  let newText = "";

  if (data.as_paragraph) {
    if (!oldText.length) {
      newText = joined;
    } else {
      newText = `${oldText}\n\n${joined}\n\n`;
    }
  } else {
    if (!oldText.length) {
      newText = joined;
    } else if (oldText.endsWith(" ")) {
      newText = oldText + joined;
    } else {
      newText = oldText + " " + joined;
    }

    if (!newText.endsWith(" ")) {
      newText += " ";
    }
  }

  meta.ctx.ui.setEditorText(newText);
  meta.ctx.ui.notify("[simple-pi] text pasted");
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
