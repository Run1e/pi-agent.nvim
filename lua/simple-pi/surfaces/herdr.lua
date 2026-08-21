local config = require("simple-pi.config")
local utils = require("simple-pi.utils")

---Surface that drives an external herdr tab/pane via its CLI.
---(implements simple_pi.Surface, declared in simple-pi/config.lua)
local M = {}

---Result of a herdr CLI invocation.
---@class simple_pi.HerdrResult
---@field error { message: string }?
---@field result table?

---@type { herdr_bin: string }
M.default_opts = {
	herdr_bin = "herdr",
}

M.opts = vim.deepcopy(M.default_opts)

---@type string?
M.tab_id = nil

---@type string?
M.pane_id = nil

---Run a herdr CLI subcommand and decode its JSON output.
---@param args string[]
---@return simple_pi.HerdrResult
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

---@param opts table?
---@return simple_pi.Surface
function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", vim.deepcopy(M.default_opts), opts or {})
	return M
end

---Create a herdr tab and launch pi in its root pane.
---@param pi simple_pi
---@return boolean?
function M.open(pi)
	M.tab_id = nil
	M.pane_id = nil

	local data = herdr_run({ "tab", "create", "--cwd", vim.fn.getcwd() })
	if data.error then
		utils.info("Failed to create herdr tab: " .. data.error.message)
		return false
	end

	if not data.result or not data.result.root_pane then
		utils.error("Failed to create Herdr tab")
		return false
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
		utils.error("Failed to launch Pi in herdr: " .. data.error.message)
		return false
	end

	return true
end

---Close the herdr tab.
---@return boolean
function M.close()
	-- this will kill the pi instance if it's still running there? do we even want that?
	-- I mean it's kind of semantically what close would mean in this situation
	if M.tab_id == nil then
		return true
	end

	local data = herdr_run({ "tab", "close", M.tab_id })

	if data.error then
		utils.error("Failed to close herdr tab: " .. data.error.message)
		return false
	end

	M.tab_id = nil
	M.pane_id = nil

	return true
end

---Focus the herdr tab.
---@return boolean
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

-- check if herdr_bin actually exists
-- we could also check for ACCESS_X I guess
function M.validate()
	if not vim.fn.executable(M.opts.herdr_bin) then
		utils.raise(string.format("'%s' is not executable", M.opts.herdr_bin))
	end
end

return M
