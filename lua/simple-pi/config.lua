local M = {}

---@class simple_pi.Surface
---@field setup fun(opts: table?): simple_pi.Surface?
---@field open fun(pi: simple_pi): boolean?
---@field close fun(): boolean
---@field focus fun(): boolean

---@class simple_pi.SetQflistToolOpts
---@field enabled boolean
---@field on_update fun()?

---@class simple_pi.ToolsOpts
---@field disable_all boolean
---@field nvim_get_qflist { enabled: boolean }
---@field nvim_set_qflist simple_pi.SetQflistToolOpts
---@field [string] any

---@class simple_pi.Opts
---@field surface simple_pi.Surface
---@field pi_bin string
---@field focus_on_open boolean
---@field close_on_disconnect boolean
---@field tools simple_pi.ToolsOpts

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
	assert(opts, "simple-pi: call setup() before using the plugin")
	return opts
end

---@param opts simple_pi.Opts?
function M.setup(opts)
	M._opts = vim.tbl_deep_extend("force", vim.deepcopy(M.default_opts), opts or {})

	-- default to nvim surface
	if M.get_opts().surface == nil then
		M.get_opts().surface = require("simple-pi.surfaces.nvim")
	end
end

return M
