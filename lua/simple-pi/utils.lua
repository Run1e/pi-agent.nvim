local M = {}

function M.info(msg, opts)
	M.notify(msg, vim.log.levels.INFO, opts)
end

function M.warn(msg, opts)
	M.notify(msg, vim.log.levels.WARN, opts)
end

function M.error(msg, opts)
	M.notify(msg, vim.log.levels.ERROR, opts)
end

function M.inspect(data)
	M.info(vim.inspect(data))
end

function M.notify(msg, level, opts)
	vim.schedule(function()
		pcall(vim.notify, "[simple-pi] " .. msg, level, opts)
	end)
end

function M.raise(msg)
	error("[simple-pi] " .. msg)
end

function M.make_session_name()
	return string.format("simple-pi-%s-%03d", os.date("%Y-%m-%dT%H-%M-%S"), vim.uv.now() % 1000)
end

function M.get_socket_dir()
	local tmp_dir = "/tmp"
	local ideal_dir = os.getenv("XDG_RUNTIME_DIR")

	if ideal_dir == nil or #ideal_dir == 0 or vim.uv.fs_access(ideal_dir, "w") ~= true then
		return tmp_dir
	end

	ideal_dir = ideal_dir .. "/simple-pi"
	vim.uv.fs_mkdir(ideal_dir, tonumber("700", 8))

	-- fall back to base if we couldn't make it usable
	if vim.uv.fs_access(ideal_dir, "w") ~= true then
		return tmp_dir
	end

	return ideal_dir
end

function M.make_pi_launch_command(pi_bin, session_name)
	return {
		pi_bin,
		"-e",
		M.get_extension_path(),
		"--session-id",
		session_name,
	}
end

function M.get_extension_path()
	local current_file = debug.getinfo(1, "S").source:gsub("^@", "")
	local dir = vim.fn.fnamemodify(current_file, ":p:h:h")
	return dir .. "/../extension/simple-pi.ts"
end

function M.get_buf_name(buf)
	local buf_name = vim.api.nvim_buf_get_name(buf)

	-- ignore unsaved/scratch buffers
	if buf_name == "" then
		return nil
	end

	return vim.fn.fnamemodify(buf_name, ":.")
end

return M
