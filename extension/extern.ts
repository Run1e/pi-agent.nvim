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
  test_command: { hello: string };
};

export type NvimCommandResults = {
  nvim_get_qflist: string[];
  nvim_set_qflist: number;
  test_command: { ret: string };
};

export type NvimEvents = {
  register_event_interest: {
    event_name: string;
    blocking: boolean;
  };
};
