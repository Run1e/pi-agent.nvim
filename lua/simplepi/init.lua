local config = require("simplepi.config")
local server = require("simplepi.server")
local listeners = require("simplepi.listeners")

local M = {}

function M.make_session_name()
	return string.format("simplepi-%s-%03d", os.date("%Y-%m-%dT%H-%M-%S"), vim.uv.now() % 1000)
end

function M.make_pi_launch_command()
	return {
		"pi",
		"-e",
		M.get_extension_path(),
		"--session-id",
		M.session_name,
	}
end

function M.setup(opts)
	config.setup(opts)

	M.next_id = 1
	M.session_name = nil
	M.socket_path = nil
end

function M.start()
	-- if already running, just dispatch focus instead
	if M.ready() then
		M.focus()
		return
	end

	M.session_name = M.make_session_name()
	M.socket_path = "/tmp/" .. M.session_name
	server.start(M.socket_path, M.on_connect, M.on_disconnect, M.on_message)

	config.opts.surface.open(M)

	if config.opts.focus_on_open then
		config.opts.surface.focus()
	end
end

function M.get_surface(name)
	local default_surfaces = {
		nvim = true,
		tmux = true,
		herdr = true,
	}

	if not default_surfaces[name] then
		vim.notify(
			string.format(
				"'%s' is not a valid surface, options are %s. Defaulting to 'nvim'.",
				name,
				table.concat(vim.tbl_keys(default_surfaces), ", ")
			),
			vim.log.levels.ERROR
		)

		name = "nvim"
	end

	return require("simplepi.surfaces." .. name)
end

function M.get_extension_path()
	local current_file = debug.getinfo(1, "S").source:gsub("^@", "")
	local dir = vim.fn.fnamemodify(current_file, ":p:h:h")
	return dir .. "/../extension/simplepi.ts"
end

function M.ready()
	return server.is_active()
end

function M.ready_guard()
	if not M.ready() then
		vim.notify("Not connected to Pi, run require('simplepi').start()")
		return false
	end

	return true
end

function M.send_command(command, data)
	if not M.ready_guard() then
		return
	end

	-- would've loved a uuid for the id but eh this is fine?
	server.send({ id = M.next_id, command = command, data = data })
	M.next_id = M.next_id + 1
end

function M.on_message(msg)
	local listener = listeners[msg.event]
	if listener then
		listener(msg.data)
	end
end

function M.on_connect()
	vim.notify("Connected to Pi :D")
end

function M.on_disconnect()
	vim.notify("Pi disconnected D:")
	config.opts.surface.close()
end

function M.ping()
	M.send_command("ping", {})
end

function M.add_text(text)
	M.send_command("addText", { text = text })
end

function get_buf_name(buf)
	local buf_name = vim.api.nvim_buf_get_name(buf)

	-- ignore unsaved/scratch buffers
	if buf_name == "" then
		return nil
	end

	return vim.fn.fnamemodify(buf_name, ":.")
end

function M.focus()
	if not M.ready_guard() then
		return false
	end

	return config.opts.surface.focus()
end

function M.close()
	if not M.ready_guard() then
		return false
	end

	return config.opts.surface.close()
end

function M.paste_line_reference()
	if not M.ready_guard() then
		return false
	end

	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_get_current_buf()
	local line = vim.api.nvim_win_get_cursor(win)

	local buf_name = get_buf_name(buf)

	if buf_name == nil then
		-- TODO: add notify error
		return false
	end

	M.add_text(buf_name .. ":" .. line[1])

	return true
end

function M.paste_range_reference(opts)
	if not M.ready_guard() then
		return false
	end

	local mode = vim.fn.mode()
	if (mode ~= "v") and (mode ~= "V") and (mode ~= "\22") then
		vim.notify("Not in visual mode", vim.log.levels.WARN)
		return false
	end

	-- unfortunately you need to exit visual mode for the < and > marks to update properly
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, false, true), "x", true)

	local buf = vim.api.nvim_get_current_buf()
	local start_mark = vim.api.nvim_buf_get_mark(buf, "<")
	local end_mark = vim.api.nvim_buf_get_mark(buf, ">")

	if opts ~= nil and opts.retain_mode == true then
		vim.cmd("normal! gv")
	end

	local buf_name = get_buf_name(buf)

	if buf_name == nil then
		-- TODO: add notify error
		return false
	end

	local start_line = start_mark[1]
	local end_line = end_mark[1]

	M.add_text(buf_name .. ":" .. start_line .. "-" .. end_line)

	return true
end

return M
