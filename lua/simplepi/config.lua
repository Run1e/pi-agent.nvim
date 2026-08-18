local M = {}

local default_surfaces = {
	nvim = true,
	tmux = true,
	herdr = true,
}

M.default_opts = {
	surface = nil,
	focus_on_open = true,
}

M.opts = nil

function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", vim.deepcopy(M.default_opts), opts or {})

	if not M.opts.surface.check() then
		vim.notify("Failed to perform surface checks", vim.log.levels.ERROR)
	end
end

return M
