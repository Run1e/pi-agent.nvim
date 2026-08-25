# pi-agent.nvim

Pragmatic integration between Neovim and the [pi agent harness](https://pi.dev/).

## Features

- Open pi inside a Neovim window/tab, or in a new terminal multiplexer tab (tmux/herdr)
- Send context directly from Neovim; line/range references, selected range, etc
- Let your agent read and edit the quickfix list via tools (`nvim_get_qflist`, `nvim_set_qflist`)
- Trigger Lua functions on [pi events](https://pi.dev/docs/latest/extensions#events): `pi.on("agent_settled", function() ... end)`
- pi extension bundled with plugin, no extra dependencies, built to be hackable

### Tools

#### `nvim_get_qflist` / `nvim_set_qflist`

Let your agent access and edit the quickfix list.

Try asking:
- `explain everything in my quickfix list`
- `review @file and put issues in my qflist`
- `find all instances of exception swallowing and put them in my qflist`

### Listen to events

Listen to arbitrary [pi events](https://pi.dev/docs/latest/extensions#events) in Neovim:

```lua
-- .on listens to events asynchronously and does not block the pi event handler
pi.on("agent_settled", function(event) vim.notify("Agent settled!") end)

-- .on_blocking *does* block the pi event handler and uses this return value on the pi side
pi.on_blocking("message_end", function(event)
	if event.message.role == "user" then
		event.message.content[1].text = event.message.content[1].text .. " -- btw: hello from pi-agent!"
		return event
	end
end)
```

`pi.on_blocking` will let you modify pi behaviour through the return value, though very complicated
(or security critical) use-cases are often better off as
an [actual pi extension](https://pi.dev/docs/latest/extensions).
The input `event` and the return value (in the case of `pi_blocking`) are JSON-serialized
over the socket.

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

### Set up your surface

pi-agent supports three "surfaces" out of the box: `nvim`, `herdr`, and `tmux`.

To set a specific surface:
```lua
local pi = require("pi-agent")
pi.setup({
    surface = pi.get_surface("herdr")
})
```

You can also further configure the surface by calling `.configure()`:
```lua
pi.setup({
    surface = pi.get_surface("nvim").configure({
        open_in = "tab", -- open pi in a new tab instead of a vsplit
        auto_insert_on_focus = true, -- automatically enter insert mode when navigating to pi
        -- etc...
    })
})
```

Surface implementations are just Lua modules, so you can provide your own (see below).

### Keymaps

pi-agent ships with no default keymaps.

Here's a list of recommended defaults to get you started:
```lua
vim.keymap.set("n", "<leader>as", pi.start, { desc = "pi: Start" })
vim.keymap.set("n", "<leader>ac", pi.close, { desc = "pi: Close" })
vim.keymap.set({ "n", "x" }, "<leader>al", pi.paste_line_reference, { desc = "pi: Paste line reference" })
vim.keymap.set({ "n", "x" }, "<leader>ar", pi.paste_range_reference, { desc = "pi: Paste range reference" })
vim.keymap.set({ "n", "x" }, "<leader>ap", pi.paste_selection, { desc = "pi: Paste selection" })
```

## Interface and options reference

### API reference

Some methods take a callback as an optional `cb` parameter that is called on success, failure, and timeout:

```lua
pi.paste_range_reference(function(result)
	---@field ok boolean
	---@field reason ("command_success"|"command_failure"|"timeout"|"error")?
	---@field error string?
	---@field value any?

	if result.ok then
		vim.notify("Successfully pasted range reference")
	else
		vim.notify("Failed pasting range reference, reason: " .. result.reason .. " error: " .. result.error)
	end
end)

```

| Method | Description |
| ------- | -------- |
| pi.get_surface(name) | Get a reference to the module that implements the surface |
| pi.start() | Start pi in the provided surface, or focus if already started |
| pi.on(name, function(event) ... end) | Listen to any pi event |
| pi.on_blocking(name, function(event) ... end) | Same as above but sends the return value back to pi to be returned in the real event handler |
| pi.focus(cb) | Focus on the pi instance |
| pi.paste_line_reference(cb) | Paste a line reference (`file:linenum`) of your current line into your pi prompt |
| pi.paste_range_reference(cb) | Paste a range reference (`file:startline:endline`) of your current selection into your pi prompt |
| pi.paste_selection(cb) | Paste your current selection contents into your pi prompt |
| pi.paste_qflist(cb) | Paste your quickfix list into your pi prompt |
| pi.close(cb) | Close the window/tab pi is running in (will kill pi unless surface == "nvim") |
| pi.stop() | Stop the socket server |

### Options reference

#### Default plugin options

```lua
require("pi-agent").setup({
	-- this will be forced to be the nvim surface if passed in as nil
	surface = nil, 

	-- set a custom pi binary path
	pi_bin = "pi",

	-- whether to focus pi when it starts
	focus_on_open = true,

	-- whether to close the pi window/tab on disconnect
	close_on_disconnect = true,

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

#### nvim surface options

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

#### herdr surface options

```lua
{
	-- set a custom herdr binary
	herdr_bin = "herdr",
}
```

#### tmux surface options

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
	pi.paste_line_reference(function(res)
		if res.ok then
			pi.focus()
		end
	end)
end, { desc = "pi: Paste line reference" })

```

### Notify on agent settled

```lua
pi.on("agent_settled", function(event)
	vim.notify("Agent settled")
	-- wouldn't recommend it but you could pi.focus() here
end)
```

## Planned

- LSP tools (`nvim_get_diagnostics`)
- Compose pi messages in a Neovim scratch buffer
- Support for more surfaces like cmux and zellij

