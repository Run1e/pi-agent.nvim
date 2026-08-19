import { Meta } from "./dispatcher";

export type PiCommands = {
  sendData: { type: string; name: string; correlationId: number; data: object };
  addText: { text: string };
  ping: {};
};

export type PiCommand<K extends keyof PiCommands = keyof PiCommands> = {
  [K2 in K]: { correlationId: number; name: K2; data: PiCommands[K2] };
}[K];

export type CommandHandler<K extends keyof PiCommands> = (
  meta: Meta,
  data: PiCommands[K],
) => void;

export const handleAddText: CommandHandler<"addText"> = (meta, data) => {
  // TODO: possible to insert where the users' cursor is?
  // there's "pasteToEditor" but that doesn't let us do spacing particularly well...
  const oldText = meta.ctx.ui.getEditorText();
  let newText = "";

  if (!oldText.length) {
    newText = data.text;
  } else if (oldText.endsWith(" ")) {
    newText = oldText + data.text;
  } else {
    newText = oldText + " " + data.text;
  }

  if (!newText.endsWith(" ")) {
    newText += " ";
  }

  meta.ctx.ui.setEditorText(newText);
  meta.ctx.ui.notify("[simple-pi] text pasted");
};

export const handlePing: CommandHandler<"ping"> = (meta, data) => {
  meta.sendEvent("pong", {});
};
