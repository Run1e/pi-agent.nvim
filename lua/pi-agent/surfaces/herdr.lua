local config = require("pi-agent.config")
local utils = require("pi-agent.utils")

local M = {}

---@class pi_agent.surfaces.herdr.Opts
---@field herdr_bin string

---Result of a herdr CLI invocation.
---@class pi_agent.surfaces.herdr.CommandResult
---@field error { message: string }?
---@field result table?

---@type pi_agent.surfaces.herdr.Opts
M.default_opts = {
	herdr_bin = "herdr",
}

---@type pi_agent.surfaces.herdr.Opts
M.opts = vim.deepcopy(M.default_opts)

---@type string?
M.tab_id = nil

---@type string?
M.pane_id = nil

---Run a herdr CLI subcommand and decode its JSON output.
---@param args string[]
---@return pi_agent.surfaces.herdr.CommandResult
local function herdr_run(args)
	---@type string[]
	local cmd = { M.opts.herdr_bin }
	vim.list_extend(cmd, args)

	local completed = vim.system(cmd, { text = true }):wait(2500)

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

function M.setup()
	-- nothing to setup
end

---@param opts pi_agent.surfaces.herdr.Opts?
---@return pi_agent.Surface
function M.configure(opts)
	M.opts = vim.tbl_deep_extend("force", vim.deepcopy(M.default_opts), opts or {})
	return M
end

---@param pi pi_agent.Pi
function M.open(pi)
	M.tab_id = nil
	M.pane_id = nil

	local data = herdr_run({ "tab", "create", "--cwd", vim.fn.getcwd() })
	if data.error then
		utils.raise("Failed to create herdr tab: " .. data.error.message)
	end

	if not data.result or not data.result.root_pane then
		utils.raise("Failed to create Herdr tab")
	end

	M.tab_id = data.result.tab.tab_id
	M.pane_id = data.result.root_pane.pane_id

	---@type string[]
	local cmd = {
		"pane",
		"run",
		M.pane_id,
	}

	vim.list_extend(cmd, utils.make_pi_launch_command(config.get_opts().pi_bin, assert(pi.session_name)))

	data = herdr_run(cmd)
	if data.error then
		utils.raise("Failed to launch Pi in herdr: " .. data.error.message)
	end
end

function M.close()
	-- this will kill the pi instance if it's still running there? do we even want that?
	-- I mean it's kind of semantically what close would mean in this situation
	if M.tab_id == nil then
		return
	end

	local data = herdr_run({ "tab", "close", M.tab_id })

	if data.error then
		utils.raise("Failed to close herdr tab: " .. data.error.message)
	end

	M.tab_id = nil
	M.pane_id = nil
end

function M.focus()
	if M.tab_id == nil or M.pane_id == nil then
		utils.raise("No herdr tab or pane id")
	end

	local data = herdr_run({ "tab", "focus", M.tab_id })

	if data.error then
		utils.raise("herdr tab focus failed: " .. data.error.message)
	end
end

-- check if herdr_bin actually exists
-- we could also check for ACCESS_X I guess
function M.validate()
	if not vim.fn.executable(M.opts.herdr_bin) then
		utils.raise(string.format("'%s' is not executable", M.opts.herdr_bin))
	end

	if vim.env.HERDR_ENV == nil or vim.env.HERDR_ENV == "" then
		utils.raise("nvim is not running inside herdr")
	end
end

return M
