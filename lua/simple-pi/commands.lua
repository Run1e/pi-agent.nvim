local utils = require("simple-pi.utils")
local config = require("simple-pi.config")

local M = {}

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
		local filename = vim.fn.fnamemodify(e.file, ":p")
		local text

		if e.special_comment == nil then
			-- TODO: this is a really naive way to go about this
			-- we should check if a buffer is already open with the file
			local ok, lines = pcall(vim.fn.readfile, filename, "", e.lnum)
			if ok and lines[#lines] ~= nil then
				text = lines[#lines]
			end
		else
			text = e.special_comment
		end

		table.insert(items, {
			filename = filename,
			lnum = e.lnum,
			col = e.col,
			text = text,
		})
	end

	local action_map = {
		replace = "u",
		append = "a",
	}

	local result = vim.fn.setqflist(items, action_map[data.action])
	if result ~= 0 then
		utils.raise("Failed setting quickfix list, result code: " .. tostring(result))
	end

	local on_update = config.opts.tools.nvim_set_qflist.on_update
	if on_update ~= nil then
		on_update()
	end

	return #vim.fn.getqflist()
end

return M
