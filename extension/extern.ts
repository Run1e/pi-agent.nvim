export type NvimCommands = {
  nvim_get_qflist: null;
  nvim_set_qflist: {
    entries: {
      file: string;
      lnum: number;
      col: number;
      special_command?: string;
    }[];
  };
  test_command: { hello: string };
};

export type NvimCommandResults = {
  nvim_get_qflist: string[];
  nvim_set_qflist: number;
  test_command: { ret: string };
};
