# 🤖 `pi-agent.nvim`

Pragmatic integration between Neovim and the [pi agent harness](https://pi.dev/).

- [Quickstart](#quickstart)
    - [Install](#install)
    - [Setup](#setup)
- [API reference](#api-reference)
    - [Methods](#methods)
    - [Options](#options)
- [Recipies](#recipies)

## ✨ Features

- Open pi inside a Neovim window/tab, or in a new terminal multiplexer tab (tmux/herdr)
- Send context directly from Neovim; cursor/selection locations, selection contents, etc
- Let your agent read and edit the quickfix list via tools (`nvim_get_qflist`, `nvim_set_qflist`)
- Trigger Lua functions on [pi events](https://pi.dev/docs/latest/extensions#events): `pi.on("agent_settled", function() ... end)`
- pi extension bundled with plugin, no extra dependencies, built to be hackable

### 🔧 Tools

#### `nvim_get_qflist` / `nvim_set_qflist`

Let your agent access and edit the quickfix list.

Try asking:
- `explain everything in my quickfix list`
- `review last commit and put issues in my qflist`
- `find all instances of exception swallowing and put them in my qflist`

### 📡 Listen to events

Listen to arbitrary [pi events](https://pi.dev/docs/latest/extensions#events) in Neovim:

```lua
-- .on listens to events asynchronously and does not block the pi event handler
pi.on("agent_settled", function(event) vim.notify("Agent settled!") end)

-- .on_blocking *does* block the pi event handler and uses this return value on the pi side
pi.on_blocking("message_end", function(event)
	if event.message.role == "user" then
		event.message.content[1].text = event.message.content[1].text
			.. " -- btw: hello from pi-agent.nvim!"
		return event
	end
end)
```

### 📎 Passing context

You can paste text to your in-progress pi message/prompt in multiple ways:

| Method | Description |
| - | - |
| `paste_cursor_location()` | paste current cursor location (`file:linenum`) |
| `paste_selection_location()` | paste current selection location (`file:startline-endline`) |
| `paste_selection_contents()` | paste current selection contents |
| `paste_qflist()` | paste quickfix list |

## Quickstart

### Install

```lua
-- lazy.nvim
return {
	"Run1e/pi-agent.nvim",
	config = function()
		require("pi-agent").setup()
		-- add your keymaps here...
	end,
}

-- vim.pack
vim.pack.add({ "https://github.com/Run1e/pi-agent.nvim"})
require("pi-agent").setup()
-- add your keymaps here...
```

### Setup

pi-agent supports three "surfaces" (where your pi instance runs) out of the box:
`nvim`, `herdr`, and `tmux`.

If omitted it defaults to opening pi in a Neovim vsplit.

To set a specific surface, for example [herdr](https://herdr.dev/):
```lua
local pi = require("pi-agent")
pi.setup({
    surface = pi.get_surface("herdr")
})
```

All surfaces have their on options you can configure, see [surface options](#surface-options)

### Keymaps

pi-agent ships with no default keymaps.

Here's a list of recommended defaults to get you started:
```lua
vim.keymap.set("n", "<leader>as", pi.start, { desc = "pi: Start" })
vim.keymap.set("n", "<leader>af", pi.focus, { desc = "pi: Focus" })
vim.keymap.set("n", "<leader>ac", pi.close, { desc = "pi: Close" })
vim.keymap.set({ "n", "x" }, "<leader>al", pi.paste_cursor_location, { desc = "pi: Paste cursor location" })
vim.keymap.set({ "n", "x" }, "<leader>ar", pi.paste_selection_location, { desc = "pi: Paste range location" })
vim.keymap.set({ "n", "x" }, "<leader>ap", pi.paste_selection_contents, { desc = "pi: Paste selection contents" })
```

See [Methods](#methods) for other functionality you can map.

## API Reference

### Methods

Some methods take a callback as an optional `cb` parameter that is called on success, failure, and timeout:

```lua
pi.paste_range_location(function(result)
	---@field ok boolean
	---@field reason ("command_success"|"command_failure"|"timeout"|"error")?
	---@field error string?
	---@field value any?

	if result.ok then
		vim.notify("Successfully pasted range location, focusing pi")
		pi.focus()
	else
		-- handle failure if needed
	end
end)
```

`pi.on_blocking` will let you modify pi behaviour through the return value, though very complicated
(or security critical) use-cases are often better off as
an [actual pi extension](https://pi.dev/docs/latest/extensions).
The input `event` and the return value (in the case of `pi_blocking`) are JSON-serialized
over the socket.


| Method | Description |
| ------- | -------- |
| **get_surface**(name) | Get the Lua surface module |
| **start**() | Start pi, or focus if already started |
| **on**(name, function(event) ... end) | Listen to any pi event (asynchronously) |
| **on_blocking**(name, function(event) ... end) | Same as above but sends the return value back to pi to be returned in the real event handler |
| **focus**(cb) | Focus on the pi instance |
| **paste_cursor_location**(cb) | Paste cursor location (`file:linenum`) into pi prompt |
| **paste_selection_location**(cb) | Paste range location (`file:startline-endline`) into pi prompt |
| **paste_selection_contents**(cb) | Paste the current selection contents into your pi prompt |
| **paste_qflist**(cb) | Paste your quickfix list into pi prompt |
| **close**(cb) | Close the window/tab pi is running in (will kill pi process unless surface is nvim) |
| **stop**() | Stop the socket server |

### Options

```lua
require("pi-agent").setup({
	-- defaults to nvim surface if nil
	surface = nil, 

	-- set a custom pi binary path
	pi_bin = "pi",

	-- whether to focus pi when it starts
	focus_on_open = true,

	-- whether to close the pi window/tab on disconnect
	close_on_disconnect = false,

	-- tools configuration
	tools = {
		disable_all = false,

		nvim_get_qflist = {
			enabled = true,
		},

		nvim_set_qflist = {
			enabled = true,

			-- called when the qflist is updated
			on_update = nil,
		},
	},
})
```

---

You can configure surfaces by calling `.configure()` on them, which also returns the module itself for convenience.

Here we make pi open in a new Neovim tab instead of a vsplit, and automatically enter insert on focus:
```lua
pi.setup({
    surface = pi.get_surface("nvim").configure({
        open_in = "tab", -- open pi in a new tab instead of a vsplit
        auto_insert_on_focus = true, -- automatically enter insert mode when navigating to pi
        -- etc...
    })
})
```

Surface implementations are just Lua modules, so you can provide your own shaped like `pi_agent.Surface`.

### Surface options

#### `nvim` surface options

```lua
{
	-- window | tab -- where to open pi
	open_in = "window",

	-- set up autocmd that enters insert mode when focusing on pi
	auto_insert_on_focus = true,

	-- right | left | top | bottom -- which way to split
	split = "right",

	-- what size to give the pi window in a split
	size_ratio = 0.4,
}
```

#### `herdr` surface options

```lua
{
	-- set a custom herdr binary
	herdr_bin = "herdr",
}
```

#### `tmux` surface options

```lua
{
	-- set a custom tmux binary path
	tmux_bin = "tmux",
}
```

## Recipies

### Automatically focus on successful commands

```lua
vim.keymap.set({ "n", "x" }, "<leader>al", function()
	pi.paste_cursor_location(function(res)
		if res.ok then
			pi.focus()
		end
	end)
end, { desc = "pi: Paste line location" })
```

### Open/close quickfix list on populate/clear

```lua
pi.setup({
	tools = {
		nvim_set_qflist = {
			on_update = function()
				vim.cmd(#vim.fn.getqflist() ~= 0 and "copen" or "cclose")
			end,
		},
	},
})
```

### Sending arbitrary text to pi

Part of the internal API, subject to change.

```lua
pi.send(cb or nil, "command", "append_text", { lines = { "list", "of", "lines" }, as_paragraph = false})
```

## Planned

- LSP tools (`nvim_get_diagnostics`)
- Compose pi messages in a Neovim scratch buffer
- Support for more surfaces like cmux and zellij
- I did experiment with tools for marks/registers but they proved to be relatively useless?

