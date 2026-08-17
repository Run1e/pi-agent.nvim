import {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

export type Protocol = {
  addText: { text: string };
  ping: {};
};

export type Command<K extends keyof Protocol = keyof Protocol> = {
  [K2 in K]: { id: number; command: K2; data: Protocol[K2] };
}[K];

export const handlers: {
  [K in keyof Protocol]: (
    pi: ExtensionAPI,
    ctx: ExtensionContext,
    sendEvent: (eventName: string, data: object) => void,
    data: Protocol[K],
  ) => void;
} = {
  addText: (pi, ctx, sendEvent, data) => {
    // TODO: possible to insert where the users' cursor is?
    // there's "pasteToEditor" but that doesn't let us do spacing particularly well...
    const oldText = ctx.ui.getEditorText();
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

    ctx.ui.setEditorText(newText);
    ctx.ui.notify("simplepi: text pasted");
  },

  ping: (pi, ctx, sendEvent, data) => {
    sendEvent("pong", {});
  },
};
