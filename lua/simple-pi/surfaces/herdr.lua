local utils = require("simple-pi.utils")
local config = require("simple-pi.config")

local M = {}

M.default_opts = {}

M.opts = vim.deepcopy(M.default_opts)

M.tab_id = nil
M.pane_id = nil

-- TODO: double-check all of these failure paths (do we always get json.error with .message?)

local function herdr_run(args)
	local ok, output, data

	local cmd = { "herdr" }
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

	ok, data = pcall(vim.json.decode, completed.stdout)

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
	-- TODO: should we check if pi is even still running in the tab before we close it?
	vim.schedule(function()
		local data = herdr_run({ "tab", "close", M.tab_id })

		-- TODO: check actual output
		if data.error then
			utils.error("Failed to close herdr tab: " .. data.error.message)
			return
		end

		M.tab_id = nil
		M.pane_id = nil
	end)

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

-- check if herdr binary exists
function M.check()
	return true
end

return M
