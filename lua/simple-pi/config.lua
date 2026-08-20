local utils = require("simple-pi.utils")

local M = {}

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
			on_edit = nil,
		},

		nvim_get_register = {
			enabled = true,
		},
	},
}

M.opts = nil

function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", vim.deepcopy(M.default_opts), opts or {})

	-- default to nvim surface
	if M.opts.surface == nil then
		M.opts.surface = require("simple-pi.surfaces.nvim")
	end

	if not M.opts.surface.check() then
		utils.error("Failed to perform surface checks")
	end
end

return M
