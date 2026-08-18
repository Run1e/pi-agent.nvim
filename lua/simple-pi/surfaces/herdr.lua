local M = {}

M.default_opts = {}

M.opts = vim.deepcopy(M.default_opts)

M.tab_id = nil
M.pane_id = nil

-- TODO: double-check all of these failure paths (do we always get json.error with .message?)

function M.setup(opts)
	vim.tbl_deep_extend("force", vim.deepcopy(M.default_opts), opts or {})
	return M
end

function M.open(pi)
	M.tab_id = nil
	M.pane_id = nil

	local result = vim.fn.system({
		"herdr",
		"tab",
		"create",
		"--cwd",
		vim.fn.getcwd(),
	})

	local json = vim.json.decode(result)
	if not json or not json.result or not json.result.root_pane then
		vim.notify("Failed to create Herdr tab", vim.log.levels.ERROR)
		return false
	end

	M.tab_id = json.result.tab.tab_id
	M.pane_id = json.result.root_pane.pane_id

	local cmd = {
		"herdr",
		"pane",
		"run",
		M.pane_id,
	}

	vim.list_extend(cmd, pi.make_pi_launch_command())

	result = vim.fn.system(cmd)
	-- TODO: check here also

	return true
end

function M.close()
	vim.schedule(function()
		result = vim.fn.system({ "herdr", "tab", "close", M.tab_id })
		M.tab_id = nil
		M.pane_id = nil
	end)

	return true
end

function M.focus()
	if M.tab_id == nil or M.pane_id == nil then
		return false
	end

	local result = vim.fn.system({
		"herdr",
		"tab",
		"focus",
		M.tab_id,
	})

	local json = vim.json.decode(result)

	if json.error ~= nil then
		vim.notify("herdr tab focus failed: " .. json.error.message, vim.log.levels.warn)
		return false
	end

	return true
end

-- check if herdr binary exists
function M.check()
	return true
end

return M
