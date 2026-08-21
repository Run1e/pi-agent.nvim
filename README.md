# simple-pi.nvim

Pragmatic integration between Neovim and the [Pi agent harness](https://pi.dev/).

## Features

- Open Pi in Neovim or a tmux/herdr tab
- Send context directly from Neovim; line/range references, buffer text around cursor, selected range, etc
- Let your agent read and edit the quickfix list via tools
- Listen to [Pi events](https://pi.dev/docs/latest/extensions#events) in Neovim through Lua
- Trigger lua functions on Pi events: `pi.listen("pi:new_session", fn)`

### PLANNED

- LSP tools (`nvim_get_diagnostics`)
- Write Pi messages in Neovim via scratch buffer (`/write`)
- cmux surface support

### Tools

#### `nvim_get_qflist` / `nvim_set_qflist`

Let your agent access and edit the quickfix list.

Try asking:
- `explain everything in my quickfix list`
- `review @file and put issues in my qflist`
- `find all instances of exception swallowing and put them in my qflist`

## Configuration

### Surface

simple-pi supports three "surfaces" out of the box: nvim, herdr, cmux, and tmux.

To set a specific surface:
```lua
local pi = require("simple-pi")
pi.setup({
    surface = pi.get_surface("herdr")
})
```

You can also further configure the surface by calling `.configure()`:
```lua
pi.setup({
    surface = pi.get_surface("nvim").configure({
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
	},
})
```
