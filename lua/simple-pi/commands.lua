local utils = require("simple-pi.utils")

local M = {}

-- Returns a |List| with all the current quickfix errors.  Each
-- list item is a dictionary with these entries:
--     bufnr	number of buffer that has the file name, use
--         |bufname()| to get the name
--     module	module name
--     lnum	line number in the buffer (first line is 1)
--     end_lnum
--         end of line number if the item is multiline
--     col	column number (first column is 1)
--     end_col	end of column number if the item has range
--     vcol	|TRUE|: "col" is visual column
--         |FALSE|: "col" is byte index
--     nr	error number
--     pattern	search pattern used to locate the error
--     text	description of the error
--     type	type of the error, 'E', '1', etc.
--     valid	|TRUE|: recognized error message
--     user_data
--         custom data associated with the item, can be
--         any type.

function M.nvim_get_qflist(data)
	local out = {}
	local list = vim.fn.getqflist()
	for _, entry in ipairs(list) do
		local text =
			string.format("%s|%d col %d|%s", utils.get_buf_name(entry.bufnr), entry.lnum, entry.col, entry.text)
		table.insert(out, text)
	end

	return out
end

function M.nvim_set_qflist(data)
	local items = {}
	for _, e in ipairs(data.entries) do
		table.insert(items, {
			filename = vim.fn.fnamemodify(e.file, ":p"),
			lnum = e.lnum,
			col = e.col,
			text = e.text or "?", -- TODO: if nil, get the line text ourselves
		})
	end

	local action_map = {
		replace = "u",
		append = "a",
	}

	local result = vim.fn.setqflist(items, action_map[data.action])
	return result == 0
end

function M.nvim_get_register(data)
	local r = data.register or '"'
	return { register = r, text = vim.fn.getreg(r), type = vim.fn.getregtype(r) }
end

return M
