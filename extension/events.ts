import { Meta } from "./dispatcher";

export type NvimEvents = {
  command_success: { correlation_id: number; value: any };
  command_failure: { correlation_id: number; error: string };
  register_event_interest: {
    event_name: string;
    blocking: boolean;
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
  if (meta._alreadyListenedTo.includes(data.event_name)) {
    return;
  }

  const castedOn = meta.pi.on as (
    event: string,
    handler: (event: any) => unknown,
  ) => void;

  castedOn(data.event_name, async (event) => {
    meta.dispatcher.sendEvent("pi_event", {
      name: data.event_name,
      event: event,
    });
  });

  meta._alreadyListenedTo.push(data.event_name);
};
