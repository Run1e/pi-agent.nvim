local utils = require("pi-agent.utils")

local M = {}

---@class pi_agent.Surface
---@field configure fun(opts: table?): pi_agent.Surface
---@field open fun(pi: pi_agent.Pi): nil
---@field close fun(): nil
---@field focus fun(): nil
---@field validate fun(): boolean

---@class pi_agent.config.ToolsOpts
---@field disable_all boolean
---@field nvim_get_qflist { enabled: boolean }
---@field nvim_set_qflist { enabled: boolean, on_update: fun()?}
---@field [string] any

---@class pi_agent.config.Opts
---@field surface pi_agent.Surface?
---@field pi_bin string
---@field focus_on_open boolean
---@field close_on_disconnect boolean
---@field tools pi_agent.config.ToolsOpts

M.valid_surfaces = {
	nvim = true,
	tmux = true,
	herdr = true,
}

---@type pi_agent.config.Opts
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

---@type pi_agent.config.Opts?
M._opts = nil

---@return pi_agent.config.Opts
function M.get_opts()
	local opts = M._opts
	assert(opts, "[pi-agent] Call setup() before using the plugin")
	assert(opts.surface, "[pi-agent] No surface set")
	return opts
end

---@param opts pi_agent.config.Opts?
function M.setup(opts)
	M._opts = vim.tbl_deep_extend("force", vim.deepcopy(M.default_opts), opts or {})

	local default_surface = require("pi-agent.surfaces.nvim")

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
