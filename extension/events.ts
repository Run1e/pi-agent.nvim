import { Meta } from "./dispatcher";
import { NvimEvents } from "./extern";

export type EventListener<K extends keyof NvimEvents> = (
  meta: Meta,
  data: NvimEvents[K],
) => void;

export const listenRegisterEventInterest: EventListener<
  "register_event_interest"
> = (meta, data) => {
  // don't double-register events bound for nvim
  const ed = meta.dispatcher.eventData;

  // register listener if not already
  if (!ed.registeredListeners.includes(data.event_name)) {
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
  }

  meta.dispatcher.eventData.registeredListeners.push(data.event_name);
  meta.dispatcher.eventData.blockingListeners.set(
    data.event_name,
    data.blocking || !!ed.blockingListeners.get(data.event_name),
  );
};
