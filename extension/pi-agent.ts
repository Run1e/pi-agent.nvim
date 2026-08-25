import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import { Dispatcher } from "./dispatcher";

import { handleAppendText, handleInit, handlePing } from "./commands";
import { listenRegisterEventInterest } from "./events";

let dispatcher: Dispatcher | null = null;

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async (event, ctx) => {
    if (!dispatcher) {
      dispatcher = new Dispatcher(pi, ctx);

      // register command handlers
      dispatcher.setHandler("init", handleInit);
      dispatcher.setHandler("ping", handlePing);
      dispatcher.setHandler("append_text", handleAppendText);

      dispatcher.addListener(
        "register_event_interest",
        listenRegisterEventInterest,
      );
    } else {
      dispatcher.updateContext(ctx);
    }
  });

  pi.on("session_shutdown", async (event, ctx) => {
    if (event.reason === "quit") return;
  });
}
