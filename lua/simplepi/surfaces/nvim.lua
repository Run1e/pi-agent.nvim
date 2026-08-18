local M = {}

M.default_opts = {
	-- "window" | "tab"
	open_in = "window",
	auto_insert_on_focus = true,
	split = "right",
	size_ratio = 0.4,
}

M.opts = vim.deepcopy(M.default_opts)

M.tab_id = nil
M.win_id = nil
M.buf_id = nil
M.job_id = nil

M.auto_insert_autocmd_id = nil

-- TODO: double-check all of these failure paths (do we always get json.error with .message?)

function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", vim.deepcopy(M.default_opts), opts or {})

	M.win_id = nil
	M.buf_id = nil
	M.job_id = nil

	if M.opts.auto_insert_on_focus and M.auto_insert_autocmd_id == nil then
		vim.api.nvim_create_autocmd("BufEnter", {
			callback = function()
				vim.defer_fn(function()
					-- just immediately insert in opencode windows I guess?
					if M.buf_id == nil then
						return
					end

					local buf_id = vim.api.nvim_get_current_buf()
					if buf_id == M.buf_id and vim.bo[buf_id].filetype == "simplepi" then
						if vim.fn.mode() ~= "i" then
							vim.cmd("startinsert")
						end

						return
					end
				end, 16)
			end,
		})

		M.auto_insert_autocmd_id = true
	elseif M.auto_insert_autocmd_id ~= nil then
		vim.api.nvim_del_autocmd(M.auto_insert_autocmd_id)
		M.auto_insert_autocmd_id = nil
	end

	return M
end

function start_term()
	local jobstart_opts = {
		cwd = vim.uv.cwd(),
		on_exit = M.close,
		pty = true,
		term = true,
	}

	M.job_id = vim.fn.jobstart(require("simplepi").make_pi_launch_command(), jobstart_opts)
end

function M.open(pi)
	-- create a buffer if we don't have one
	if M.buf_id == nil then
		M.buf_id = vim.api.nvim_create_buf(false, true)
		vim.bo[M.buf_id].filetype = "simplepi"
	end

	M.focus()

	if M.job_id == nil then
		start_term()
	end

	-- now we gotta figure out if there's a window in the current tab that has this open? (for the window case anyway)

	return true
end

function M.close()
	vim.schedule(function()
		vim.api.nvim_win_close(M.win_id, true)
	end)

	return true
end

function open_in_tab(tab_id)
	for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(tab_id)) do
		local win_buf_id = vim.api.nvim_win_get_buf(win_id)
		if win_buf_id == M.buf_id then
			return true
		end
	end

	return false
end

-- create the window if needed
function _focus_window()
	local tab_id = vim.api.nvim_get_current_tabpage()
	local currently_open = open_in_tab(tab_id)

	if not currently_open then
		local config = {
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
		M.win_id = vim.api.nvim_open_win(M.buf_id, true, config)
	else
		vim.api.nvim_set_current_win(M.win_id)
	end
end

function _focus_tab()
	if M.tab_id == nil then
		-- tab doesn't exist, create it
		M.tab_id = vim.api.nvim_open_tabpage(M.buf_id, true, {})
		M.win_id = vim.api.nvim_tabpage_get_win(M.tab_id)
	else
		if not vim.api.nvim_tabpage_is_valid(M.tab_id) or not open_in_tab(M.tab_id) then
			M.tab_id = nil
			_focus_tab()
			return
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
	end

	return true
end

-- should always be true, we're in neovim
function M.check()
	return true
end

return M
