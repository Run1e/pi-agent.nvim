import { ExtensionAPI, ToolInfo } from "@earendil-works/pi-coding-agent";
import Type from "typebox";
import { Dispatcher } from "./dispatcher";

export function registerTools(
  pi: ExtensionAPI,
  getDispatcher: () => Dispatcher,
) {
  const tools: ToolInfo[] = pi.getAllTools();

  pi.registerTool({
    name: "nvim_get_qflist",
    label: "Neovim get quickfix list",
    description: "Retrieves the Neovim quickfix list",
    promptGuidelines: [
      "Use nvim_get_qflist when you need to access the Neovim quickfix list (qflist)",
    ],
    parameters: Type.Object({}),

    async execute(_toolCallId, params, signal, onUpdate, ctx) {
      const dispatcher = getDispatcher();
      if (!dispatcher) {
        return {
          content: [{ type: "text", text: "Not connected to Neovim" }],
          details: {},
          isError: true,
        };
      }
      let res: string[] = [];

      try {
        res = (await dispatcher.invokeCommand(
          "nvim_get_qflist",
          {},
        )) as string[];
      } catch (e) {}

      return {
        content: [{ type: "text", text: (res ?? []).join("\n") }],
        details: {},
      };
    },
  });

  pi.registerTool({
    name: "nvim_set_qflist",
    label: "Neovim set quickfix list",
    description: "Set the Neovim quickfix list",
    promptGuidelines: [
      "Use nvim_set_qflist when you need to set the Neovim quickfix list (qflist)",
      "You may suggest to put data in the quickfix list for user convenience (like if you have a list of lines with errors, improvements, suggestions, etc)",
      "You can one-shot a full replacement of the quickfix list, or you can incrementally append with several nvim_set_qflist calls",
    ],
    parameters: Type.Object({
      action: Type.Enum(["replace", "append"], {
        description: "Whether to fully replace or append to the quickfix list",
      }),
      entries: Type.Array(
        Type.Object({
          file: Type.String({
            description: "File path, from CWD or absolute",
          }),
          lnum: Type.Integer({ description: "Line number (1-based)" }),
          col: Type.Integer({
            description: "Column number (1-based)",
            default: 1,
          }),
          text: Type.Optional(
            Type.String({
              description:
                "Text show for this entry. Extracted from file if omitted",
            }),
          ),
        }),
        { description: "Entries to put in the quickfix list" },
      ),
    }),

    async execute(toolCallId, params, signal, onUpdate, ctx) {
      const dispatcher = getDispatcher();
      if (!dispatcher) {
        return {
          content: [{ type: "text", text: "Not connected to Neovim" }],
          details: {},
          isError: true,
        };
      }
      const success: boolean = (await dispatcher.invokeCommand(
        "nvim_set_qflist",
        params,
      )) as boolean;

      if (success) {
        return {
          content: [{ type: "text", text: "Quickfix list updated" }],
          details: {},
        };
      } else {
        return {
          content: [{ type: "text", text: "Failed setting the qflist" }],
          details: {},
          isError: true,
        };
      }
    },
  });
}
