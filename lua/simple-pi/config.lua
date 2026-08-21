local utils = require("simple-pi.utils")

local M = {}

---@class simple_pi.Surface
---@field configure fun(opts: table?): simple_pi.Surface
---@field open fun(pi: simple_pi): nil
---@field close fun(): nil
---@field focus fun(): nil
---@field validate fun(): boolean

---@class simple_pi.SetQflistToolOpts
---@field enabled boolean
---@field on_update fun()?

---@class simple_pi.ToolsOpts
---@field disable_all boolean
---@field nvim_get_qflist { enabled: boolean }
---@field nvim_set_qflist simple_pi.SetQflistToolOpts
---@field [string] any

---@class simple_pi.Opts
---@field surface simple_pi.Surface?
---@field pi_bin string
---@field focus_on_open boolean
---@field close_on_disconnect boolean
---@field tools simple_pi.ToolsOpts

M.valid_surfaces = {
	nvim = true,
	tmux = true,
	herdr = true,
}

---@type simple_pi.Opts
M.default_opts = {
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
}

---@type simple_pi.Opts?
M._opts = nil

---@return simple_pi.Opts
function M.get_opts()
	local opts = M._opts
	assert(opts, "[simple-pi] Call setup() before using the plugin")
	assert(opts.surface, "[simple-pi] No surface set")
	return opts
end

---@param opts simple_pi.Opts?
function M.setup(opts)
	M._opts = vim.tbl_deep_extend("force", vim.deepcopy(M.default_opts), opts or {})

	local default_surface = require("simple-pi.surfaces.nvim")

	-- default to nvim surface
	if M.get_opts().surface == nil then
		M.get_opts().surface = default_surface
	else
		local ok, err = pcall(M.get_opts().surface.validate)
		if not ok then
			utils.error(string.format("Surface failed to validate with error: %s.", err))
			utils.error("Defaulting to 'nvim' surface.")
			M.get_opts().surface = default_surface
		end
	end
end

return M
