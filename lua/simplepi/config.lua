local M = {}

local default_surfaces = {
	nvim = true,
	tmux = true,
	herdr = true,
}

M.default_opts = {
	surface = "nvim_tab",
}

M.opts = nil

function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", vim.deepcopy(M.default_opts), opts or {})

	if type(opts.surface) == "string" then
		if not default_surfaces[opts.surface] then
			local keys = vim.tbl_keys(default_surfaces)
			table.sort(keys)
			local list = table.concat(keys, ", ")

			vim.notify(
				string.format(
					"'%s' is not a valid default surface. Valid values are: %s. Defaulting to 'nvim'",
					opts.surface,
					list
				)
			)

			M.opts.surface = "nvim"
		end
		M.opts.surface = require("simplepi.surfaces." .. M.opts.surface)
	end
end

return M
