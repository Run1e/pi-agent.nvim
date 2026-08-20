# simple-pi.nvim

Pragmatic integration between Neovim and the Pi harness.

## Features

- Open Pi in Neovim or a tmux/herdr tab
- Pass context to your agent; line/range references, text around cursor, selected range, etc
- Give your agent read/write access to Neovim primitives like the quickfix list, registers, or marks via tools
- Trigger lua functions on Pi events (`new_session`)

## Tools

### `nvim_get_qflist` / `nvim_set_qflist`

Let your agent access and edit the quickfix list.

Try asking:
- `what's in my quickfix list?`
- `review @file and put issues in my qflist`
- `find all instances of exception swallowing and put them in my qflist`

### `nvim_get_register`

Let your agent

## Configuration

### Surface

simple-pi supports three "surfaces" out of the box: nvim, tmux, and herdr.

To set a specific surface:
```lua
local pi = require("simple-pi")
pi.setup({
    surface = pi.get_surface("herdr")
})
```

You can also further configure the surface by calling `surface.setup`:
```lua
pi.setup({
    surface = pi.get_surface("nvim").setup({
        open_in = "tab", -- open pi in a new tab instead of a vsplit
        auto_insert_on_focus = true, -- automatically enter insert when navigating to Pi
        -- etc...
    })
})
```

Surface implementations are just Lua modules, so you can create your own.
See below for documentation on configuring default surfaces and creating your
See surface documentation below for more information on configuring (or creating new) surfaces.

### Keymaps

simple-pi ships with no default keymaps.



### Install

#### lazy.nvim

```lua
return {
	"Run1e/simple-pi.nvim",
	config = function()
		require("simple-pi").setup()
        -- add your keymaps here...
	end,
}
```

### Default options

```lua
require("simple-pi").setup({
	surface = nil,
	pi_bin = "pi",

	focus_on_open = true,
	close_on_disconnect = true,

	tools = {
		disable_all = false,

		nvim_get_qflist = {
			enabled = true,
		},

		nvim_set_qflist = {
			enabled = true,
			on_update = nil,
		},

		nvim_get_register = {
			enabled = true,
		},
	},
})
```
