local config = require("pi-agent.config")
local utils = require("pi-agent.utils")

local M = {}

---@class pi_agent.surfaces.tmux.Opts
---@field tmux_bin string

---@type pi_agent.surfaces.tmux.Opts
M.default_opts = {
	tmux_bin = "tmux",
}

---@type pi_agent.surfaces.tmux.Opts
M.opts = vim.deepcopy(M.default_opts)

---@type string?
M.window_id = nil

---@type string?
M.pane_id = nil

---@param args string[]
---@return string stdout
local function tmux_run(args)
	local cmd = { M.opts.tmux_bin }
	vim.list_extend(cmd, args)

	local completed = vim.system(cmd, { text = true }):wait(2500)

	if completed.code ~= 0 then
		error(
			"tmux CLI failed with cmd: "
				.. table.concat(cmd, " ")
				.. " (exit "
				.. tostring(completed.code)
				.. ", stderr: "
				.. tostring(completed.stderr or "")
				.. ")",
			0
		)
	end

	return completed.stdout or ""
end

function M.setup()
	-- nothing to setup
end

---@param opts pi_agent.surfaces.tmux.Opts?
---@return pi_agent.Surface
function M.configure(opts)
	M.opts = vim.tbl_deep_extend("force", vim.deepcopy(M.default_opts), opts or {})
	return M
end

---@param pi pi_agent.Pi
function M.open(pi)
	M.window_id = nil
	M.pane_id = nil

	local ok, out = pcall(tmux_run, {
		"new-window",
		"-d",
		"-P",
		"-F",
		"#{window_id} #{pane_id}",
		"-c",
		vim.fn.getcwd(),
	})

	if not ok then
		utils.raise("Failed to create tmux window: " .. out)
	end

	local parts = vim.split(out:gsub("%s+$", ""), " ", { trimempty = true })

	if not parts[1] or not parts[2] then
		utils.raise("Failed to parse window/pane ids from tmux new-window output: " .. out)
	end

	M.window_id = parts[1]
	M.pane_id = parts[2]

	local launch = utils.make_pi_launch_command(config.get_opts().pi_bin, assert(pi.session_name))
	local cmd_str = table.concat(vim.tbl_map(vim.fn.shellescape, launch), " ")

	local ok2, err = pcall(tmux_run, { "send-keys", "-t", M.pane_id, cmd_str, "Enter" })
	if not ok2 then
		utils.raise("Failed to launch Pi in tmux: " .. err)
	end
end

function M.close()
	if M.window_id == nil then
		return
	end

	local ok, err = pcall(tmux_run, { "kill-window", "-t", M.window_id })

	if not ok then
		utils.raise("Failed to close tmux window: " .. err)
	end

	M.window_id = nil
	M.pane_id = nil
end

function M.focus()
	if M.window_id == nil or M.pane_id == nil then
		utils.raise("No tmux window or pane id")
	end

	local ok, err = pcall(tmux_run, { "select-window", "-t", M.window_id })

	if not ok then
		utils.raise("tmux window focus failed: " .. err)
	end
end

function M.validate()
	if not vim.fn.executable(M.opts.tmux_bin) then
		utils.raise(string.format("'%s' is not executable", M.opts.tmux_bin))
	end

	if vim.env.TMUX == nil or vim.env.TMUX == "" then
		utils.raise("nvim is not running inside tmux")
	end
end

return M
