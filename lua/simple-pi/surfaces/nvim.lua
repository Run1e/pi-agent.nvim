local config = require("simple-pi.config")
local utils = require("simple-pi.utils")

local M = {}

---@class simple_pi.NvimSurfaceOpts
---@field open_in "window"|"tab"
---@field auto_insert_on_focus boolean
---@field split string
---@field size_ratio number

---@type simple_pi.NvimSurfaceOpts
M.default_opts = {
	-- "window" | "tab"
	open_in = "window",
	auto_insert_on_focus = true,
	split = "right",
	size_ratio = 0.4,
}

---@type simple_pi.NvimSurfaceOpts
M.opts = vim.deepcopy(M.default_opts)

---@type integer?
M.tab_id = nil

---@type integer?
M.win_id = nil

---@type integer?
M.buf_id = nil

---@type integer?
M.chan_id = nil

---@type integer?
M.autocmd_id = nil

---@param opts table?
---@return simple_pi.Surface
function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", vim.deepcopy(M.default_opts), opts or {})

	M.win_id = nil
	M.buf_id = nil
	M.chan_id = nil

	if M.opts.auto_insert_on_focus and M.autocmd_id == nil then
		M.autocmd_id = vim.api.nvim_create_autocmd("BufEnter", {
			callback = function()
				vim.defer_fn(function()
					-- just immediately insert in opencode windows I guess?
					if M.buf_id == nil then
						return
					end

					local buf_id = vim.api.nvim_get_current_buf()
					if buf_id == M.buf_id and vim.bo[buf_id].filetype == "simple-pi" then
						if vim.fn.mode() ~= "i" then
							vim.cmd("startinsert")
						end

						return
					end
				end, 16)
			end,
		})
	elseif M.autocmd_id ~= nil then
		vim.api.nvim_del_autocmd(M.autocmd_id)
		M.autocmd_id = nil
	end

	return M
end

local function start_term()
	local jobstart_opts = {
		cwd = vim.uv.cwd(),
		on_exit = function()
			pcall(M.close)
		end, -- close the tab/window on jobstart exit
		pty = true,
		term = true,
	}

	local result = vim.fn.jobstart(
		utils.make_pi_launch_command(config.get_opts().pi_bin, require("simple-pi").session_name),
		jobstart_opts
	)

	if result < 1 then
		utils.raise("Failed to jobstart Pi in Nvim surface")
	end

	if M.buf_id == nil then
		return
	end

	M.chan_id = result
	vim.bo[M.buf_id].bufhidden = "hide"
end

---@return boolean
local function is_job_valid()
	if M.chan_id == nil then
		return false
	end

	local chan_info = vim.api.nvim_get_chan_info(M.chan_id)

	-- check if dict returned is empty, if so not a valid job
	if next(chan_info) == nil then
		M.chan_id = nil
		return false
	end

	if chan_info.buf == -1 or chan_info.exitcode ~= nil then
		vim.fn.chanclose(M.chan_id)
		M.chan_id = nil
		return false
	end

	return true
end

---@param pi simple_pi
function M.open(pi)
	local has_valid_job = is_job_valid()

	-- no valid job, handle buffer first
	if not has_valid_job then
		-- do NOT reuse buffers
		if M.buf_id ~= nil then
			vim.api.nvim_buf_delete(M.buf_id, { force = true })
			M.buf_id = nil
		end

		-- create a buffer if we don't have one
		if M.buf_id == nil then
			M.buf_id = vim.api.nvim_create_buf(false, true)
			vim.bo[M.buf_id].filetype = "simple-pi"
		end
	end

	-- create tab/window if needed and focus
	M.focus()

	if not has_valid_job then
		start_term()
	end
end

function M.close()
	if M.win_id ~= nil then
		vim.api.nvim_win_close(M.win_id, true)
		M.win_id = nil
	end
end

---@return boolean
local function open_in_tab(tab_id)
	for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(tab_id)) do
		local win_buf_id = vim.api.nvim_win_get_buf(win_id)
		if win_buf_id == M.buf_id then
			return true
		end
	end

	return false
end

local function _focus_window()
	if M.buf_id == nil then
		utils.raise("No buffer id")
	end

	local tab_id = vim.api.nvim_get_current_tabpage()
	local currently_open = open_in_tab(tab_id)

	if not currently_open then
		local cfg = {
			width = math.floor(vim.o.columns * M.opts.size_ratio), -- or fixed
			height = vim.o.lines - 2,
			split = M.opts.split,

			-- relative = "editor",
			-- row = 0,
			-- col = vim.o.columns * 0.6, -- right side
			-- style = "minimal", -- no statusline/line numbers
			-- border = "single",
			-- winhighlight = "Normal:Normal",
		}

		-- vim.api.nvim_win_set_buf(M.win_id, M.buf_id)
		M.win_id = vim.api.nvim_open_win(M.buf_id, true, cfg)
	else
		-- we can't close a window that we don't have
		-- we *could* figure out what window the buffer is in?
		-- but we should be good I think
		if M.win_id == nil then
			utils.raise("No window id")
		end

		vim.api.nvim_set_current_win(M.win_id)
	end
end

local function _focus_tab()
	if M.buf_id == nil then
		utils.raise("No buffer id")
	end

	if M.tab_id == nil then
		-- tab doesn't exist, create it
		M.tab_id = vim.api.nvim_open_tabpage(M.buf_id, true, {})
		M.win_id = vim.api.nvim_tabpage_get_win(M.tab_id)
	else
		if not vim.api.nvim_tabpage_is_valid(M.tab_id) or not open_in_tab(M.tab_id) then
			M.tab_id = nil
			_focus_tab()
		else
			vim.api.nvim_set_current_tabpage(M.tab_id)
		end
	end
end

function M.focus()
	if M.opts.open_in == "window" then
		_focus_window()
	elseif M.opts.open_in == "tab" then
		_focus_tab()
	else
		utils.raise("What?")
	end
end

function M.validate()
	return true -- we're in nvim, we should be fine? lol
end

return M
