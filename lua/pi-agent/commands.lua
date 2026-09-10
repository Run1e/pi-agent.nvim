local config = require("pi-agent.config")
local utils = require("pi-agent.utils")

local M = {}

---@class pi_agent.commands.nvim_set_qflist_entry_data
---@field file string
---@field lnum integer
---@field col integer
---@field special_comment string?

---@class pi_agent.commands.nvim_set_qflist_data
---@field entries pi_agent.commands.nvim_set_qflist_entry_data[]
---@field action "replace"|"append"

---@class pi_agent.commands.nvim_get_diagnostics_data
---@field namespace_id integer?

local function format_qflist(list)
	local out = {}

	for _, entry in ipairs(list) do
		local buf_name = utils.get_buf_name(entry.bufnr)
		local text = string.format("%s|%d col %d|%s", buf_name or "", entry.lnum, entry.col, entry.text or "")
		table.insert(out, text)
	end

	return out
end

---@param _ nil
---@return string[]
function M.nvim_get_qflist(pi, _)
	local list = vim.fn.getqflist()
	return format_qflist(list)
end

---@param data pi_agent.commands.nvim_set_qflist_data
---@return integer
function M.nvim_set_qflist(pi, data)
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

	local on_update = config.get_opts().tools.nvim_set_qflist.on_update
	if on_update ~= nil then
		on_update()
	end

	return #vim.fn.getqflist()
end

---@param _ nil
---@return table<string, table<string, integer>>
function M.nvim_get_diagnostic_namespaces(pi, _)
	local out = { namespaces = {} }
	local list = vim.diagnostic.get_namespaces()

	for id, ns in pairs(list) do
		-- TODO: should we guard by ns.disabled?
		out.namespaces[ns.name] = id
	end

	return out
end

---@param _ pi_agent.commands.nvim_get_diagnostics_data
---@return string[]
function M.nvim_get_diagnostics(pi, data)
	local opts = {}
	opts.namespace = data.namespace_id

	local diagnostics = vim.diagnostic.get(nil, opts)
	local qflist = vim.diagnostic.toqflist(diagnostics)

	return format_qflist(qflist)
end

return M
