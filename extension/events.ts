export type PiEvents = {
  command_success: { correlation_id: number; value: any };
  command_failure: { correlation_id: number; message: string };
};

export type PiEvent<K extends keyof PiEvents = keyof PiEvents> = {
  [K2 in K]: { correlation_id: number; name: K2; data: PiEvents[K2] };
}[K];

export type EventListener<K extends keyof PiEvents> = (
  data: PiEvents[K],
) => void;
