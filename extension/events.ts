import { Dispatcher } from "./dispatcher";
import { NvimEvents } from "./extern";

export type EventListener<K extends keyof NvimEvents> = (
  dispatcher: Dispatcher,
  data: NvimEvents[K],
) => void;

export const listenRegisterEventInterest: EventListener<
  "register_event_interest"
> = (dispatcher, data) => {
  const ed = dispatcher.eventData;

  // register listener if not already
  if (!ed.registeredListeners.has(data.event_name)) {
    const castedOn = dispatcher.pi.on as (
      event: string,
      handler: (event: any) => unknown,
    ) => void;

    castedOn(data.event_name, async (event) => {
      // if dispatcher says we're not game just return immediately
      if (!dispatcher.isReady()) {
        return;
      }

      const correlationId = dispatcher.newCorrelationId();

      const sender = () => {
        dispatcher.sendEvent("pi_event", {
          name: data.event_name,
          correlation_id: correlationId,
          event: event,
        });
      };

      if (ed.blockingListeners.get(data.event_name) ?? false) {
        const p = dispatcher.waitForEvent(
          "pi_event_response",
          (event) => event.correlation_id === correlationId,
        );

        sender();

        let piEventResponse: NvimEvents["pi_event_response"];
        try {
          piEventResponse = await p;
        } catch (e) {
          dispatcher.ctx.ui.notify(
            `[pi-agent] Timed out waiting for blocking result for event '${data.event_name}'`,
          );
          return;
        }

        if (piEventResponse.error) {
          dispatcher.ctx.ui.notify(
            `[pi-agent] Blocking result for event '${data.event_name}' failed: ${piEventResponse.error}`,
          );
        }

        return piEventResponse.result;
      } else {
        sender();
      }
    });
  }

  dispatcher.eventData.registeredListeners.add(data.event_name);
  dispatcher.eventData.blockingListeners.set(
    data.event_name,
    data.blocking || !!ed.blockingListeners.get(data.event_name),
  );
};
