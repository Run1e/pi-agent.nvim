import { Meta } from "./dispatcher";

export type NvimEvents = {
  command_success: { correlation_id: number; value: any };
  command_failure: { correlation_id: number; error: string };
  register_event_interest: {
    event_name: string;
    blocking: boolean;
  };
  pi_event_response: {
    correlation_id: number;
    result?: any;
    error?: string;
  };
};

export type NvimEvent<K extends keyof NvimEvents = keyof NvimEvents> = {
  [Key in K]: { correlation_id: number; name: Key; data: NvimEvents[Key] };
}[K];

export type EventListener<K extends keyof NvimEvents> = (
  meta: Meta,
  data: NvimEvents[K],
) => void;

export const listenRegisterEventInterest: EventListener<
  "register_event_interest"
> = (meta, data) => {
  // don't double-register events bound for nvim
  const ed = meta.dispatcher.persistentData;

  const needsUpgrade =
    data.blocking && !ed.blockingListeners.get(data.event_name);

  if (ed.registeredListeners.includes(data.event_name) && !needsUpgrade) {
    meta.ctx.ui.notify("doesn't need to listen");
    return;
  }

  const castedOn = meta.pi.on as (
    event: string,
    handler: (event: any) => unknown,
  ) => void;

  castedOn(data.event_name, async (event) => {
    let correlationId = meta.dispatcher.newCorrelationId();

    const sender = () =>
      meta.dispatcher.sendEvent("pi_event", {
        name: data.event_name,
        correlation_id: correlationId,
        event: event,
      });

    if (ed.blockingListeners.get(data.event_name) ?? false) {
      const p = meta.dispatcher.waitForEvent(
        "pi_event_response",
        (event) => event.correlation_id === correlationId,
        0,
      );

      sender();

      const piEventResponse = await p;

      if (piEventResponse.error) {
        throw new Error(piEventResponse.error);
      }

      return piEventResponse.result;
    } else {
      sender();
    }
  });

  meta.dispatcher.persistentData.blockingListeners.set(
    data.event_name,
    data.blocking,
  );

  meta.dispatcher.persistentData.registeredListeners.push(data.event_name);
};
