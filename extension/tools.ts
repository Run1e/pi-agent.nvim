import { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import Type from "typebox";
import { Dispatcher } from "./dispatcher";

export function registerTools(
  pi: ExtensionAPI,
  dispatcher: Dispatcher,
  enabledTools: string[],
) {
  if (enabledTools.includes("nvim_get_qflist")) {
    pi.registerTool({
      name: "nvim_get_qflist",
      label: "Neovim get quickfix list",
      description: "Retrieves the Neovim quickfix list",
      promptGuidelines: [
        "Use nvim_get_qflist when you need to access the Neovim quickfix list (qflist).",
      ],
      parameters: Type.Object({}),

      async execute(_toolCallId, params, signal, onUpdate, ctx) {
        let res: string[] = [];

        res = (await dispatcher.invokeCommand(
          "nvim_get_qflist",
          {},
        )) as string[];

        const output = res.length ? res.join("\n") : "Quickfix list is empty";

        return {
          content: [
            {
              type: "text",
              text: output,
            },
          ],
          details: {},
        };
      },
    });
  }

  if (enabledTools.includes("nvim_set_qflist")) {
    pi.registerTool({
      name: "nvim_set_qflist",
      label: "Neovim set quickfix list",
      description: "Set the Neovim quickfix list",
      promptGuidelines: [
        "Use nvim_set_qflist when you need to set the Neovim quickfix list (qflist).",
        "NEVER call nvim_set_qflist unprompted, only do so after being asked to, or after suggesting it yourself and being given permission.",
        "You may suggest to put data in the quickfix list for user convenience (like if you have a list of lines with errors, improvements, suggestions, etc).",
        "You can replace the entire quickfix list in one call with action = replace, or you can incrementally append over several calls with action = append.",
        "Call nvim_set_qflist with an empty list to clear the quickfix list.",
        "If the user asks you to add a filename:lnum to the quickfix list, you may not need to read the file for context at all -- just call this tool and add it.",
      ],
      parameters: Type.Object({
        action: Type.Enum(["replace", "append"], {
          description:
            "Whether to fully replace or append to the quickfix list",
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
            special_comment: Type.Optional(
              Type.String({
                description:
                  "DO NOT put line contents here, prefer to omit this field. ONLY set this if you want to set a custom comment for this quickfix list entry",
              }),
            ),
          }),
          { description: "Entries to put in the quickfix list" },
        ),
      }),

      async execute(toolCallId, params, signal, onUpdate, ctx) {
        const entryCount: number = (await dispatcher.invokeCommand(
          "nvim_set_qflist",
          params,
        )) as number;

        return {
          content: [
            {
              type: "text",
              text: `Quickfix list successfully updated, currently has ${entryCount} entries`,
            },
          ],
          details: {},
        };
      },
    });
  }
}
