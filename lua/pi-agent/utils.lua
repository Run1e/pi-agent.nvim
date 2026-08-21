local M = {}

---@param msg string
---@param opts table?
function M.info(msg, opts)
	M.notify(msg, vim.log.levels.INFO, opts)
end

---@param msg string
---@param opts table?
function M.warn(msg, opts)
	M.notify(msg, vim.log.levels.WARN, opts)
end

---@param msg string
---@param opts table?
function M.error(msg, opts)
	M.notify(msg, vim.log.levels.ERROR, opts)
end

---@param data any
function M.inspect(data)
	M.info(vim.inspect(data))
end

---@param msg string
---@param level integer
---@param opts table?
function M.notify(msg, level, opts)
	pcall(vim.notify, "[pi-agent] " .. msg, level, opts)
end

---@param msg string
function M.raise(msg)
	error("[pi-agent] " .. msg)
end

---@return string
function M.make_session_name()
	return string.format("pi-agent-%s-%03d", os.date("%Y-%m-%dT%H-%M-%S"), vim.uv.now() % 1000)
end

---@return string
function M.get_socket_dir()
	local tmp_dir = "/tmp"
	local ideal_dir = os.getenv("XDG_RUNTIME_DIR")

	if ideal_dir == nil or #ideal_dir == 0 or vim.uv.fs_access(ideal_dir, "w") ~= true then
		return tmp_dir
	end

	ideal_dir = ideal_dir .. "/pi-agent"
	vim.uv.fs_mkdir(ideal_dir, tonumber("700", 8))

	-- fall back to base if we couldn't make it usable
	if vim.uv.fs_access(ideal_dir, "w") ~= true then
		return tmp_dir
	end

	return ideal_dir
end

---@param pi_bin string
---@param session_name string
---@return string[]
function M.make_pi_launch_command(pi_bin, session_name)
	return {
		pi_bin,
		"-e",
		M.get_extension_path(),
		"--session-id",
		session_name,
	}
end

---@return string
function M.get_extension_path()
	local info = assert(debug.getinfo(1, "S"))
	local current_file = info.source:gsub("^@", "")
	local dir = vim.fn.fnamemodify(current_file, ":p:h:h")
	return dir .. "/../extension/pi-agent.ts"
end

---@param buf integer
---@return string?
function M.get_buf_name(buf)
	if buf == 0 or buf == nil then
		return nil
	end

	local buf_name = vim.api.nvim_buf_get_name(buf)

	-- ignore unsaved/scratch buffers
	if buf_name == "" then
		return nil
	end

	return vim.fn.fnamemodify(buf_name, ":.")
end

return M
