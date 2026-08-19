export type PiEvents = {
  test: {};
};

export type PiEvent<K extends keyof PiEvents = keyof PiEvents> = {
  [K2 in K]: { correlationId: number; name: K2; data: PiEvents[K2] };
}[K];

export type EventListener<K extends keyof PiEvents> = (
  data: PiEvents[K],
) => void;
