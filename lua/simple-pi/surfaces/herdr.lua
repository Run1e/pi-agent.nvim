local utils = require("simple-pi.utils")
local config = require("simple-pi.config")

local M = {}

M.default_opts = {
	herdr_bin = "herdr",
}

M.opts = vim.deepcopy(M.default_opts)

M.tab_id = nil
M.pane_id = nil

local function herdr_run(args)
	local cmd = { M.opts.herdr_bin }
	vim.list_extend(cmd, args)

	local completed = vim.system(cmd, { text = true }):wait(1000)

	-- for these unhappy paths we "mock" the output format that herdr would give
	-- doing that, the place that invokes this function can handle our errors
	-- and actual herdr errors in the same way

	if completed.code ~= 0 then
		return { error = { message = "Failed to invoke herdr CLI with cmd: " .. table.concat(cmd, " ") } }
	end

	-- no stdout, just assume it worked if exit code didn't trip above
	if completed.stdout == nil or completed.stdout == "" then
		return {}
	end

	local ok, data = pcall(vim.json.decode, completed.stdout)

	if not ok then
		return {
			error = {
				message = "Failed to decode output json from herdr with cmd: " .. table.concat(cmd, " "),
			},
		}
	end

	if data == nil or next(data) == nil then
		return { error = { message = "herdr CLI returned no output with cmd: " .. table.concat(cmd, " ") } }
	end

	return data
end

function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", vim.deepcopy(M.default_opts), opts or {})
	return M
end

function M.open(pi)
	M.tab_id = nil
	M.pane_id = nil

	local data = herdr_run({ "tab", "create", "--cwd", vim.fn.getcwd() })
	if data.error then
		utils.info("Failed to create herdr tab: " .. data.error.message)
		return
	end

	if not data.result or not data.result.root_pane then
		utils.error("Failed to create Herdr tab")
		return false
	end

	M.tab_id = data.result.tab.tab_id
	M.pane_id = data.result.root_pane.pane_id

	local cmd = {
		"pane",
		"run",
		M.pane_id,
	}

	vim.list_extend(cmd, utils.make_pi_launch_command(config.opts.pi_bin, pi.session_name))

	data = herdr_run(cmd)
	if data.error then
		utils.error("Failed to launch Pi in herdr: " .. data.error.message)
		return false
	end

	return true
end

function M.close()
	-- this will kill the pi instance if it's still running there? do we even want that?
	-- I mean it's kind of semantically what close would mean in this situation
	local data = herdr_run({ "tab", "close", M.tab_id })

	if data.error then
		utils.error("Failed to close herdr tab: " .. data.error.message)
		return false
	end

	M.tab_id = nil
	M.pane_id = nil

	return true
end

function M.focus()
	if M.tab_id == nil or M.pane_id == nil then
		return false
	end

	local data = herdr_run({ "tab", "focus", M.tab_id })

	if data.error then
		utils.warn("herdr tab focus failed: " .. data.error.message)
		return false
	end

	return true
end

return M
