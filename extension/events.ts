export type PiEvents = {
  command_success: { correlation_id: number; value: any };
  command_failure: { correlation_id: number; error: string };
};

export type PiEvent<K extends keyof PiEvents = keyof PiEvents> = {
  [Key in K]: { correlation_id: number; name: Key; data: PiEvents[Key] };
}[K];

export type EventListener<K extends keyof PiEvents> = (
  data: PiEvents[K],
) => void;
