export type NvimCommands = {
  nvim_get_qflist: null;
  nvim_set_qflist: {
    action: string;
    entries: {
      file: string;
      lnum: number;
      col: number;
      special_comment?: string;
    }[];
  };
};

export type NvimCommandResults = {
  nvim_get_qflist: string[];
  nvim_set_qflist: number;
};

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
