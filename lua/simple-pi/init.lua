local config = require("simple-pi.config")
local server = require("simple-pi.server")
local commands = require("simple-pi.commands")
local events = require("simple-pi.events")
local utils = require("simple-pi.utils")

local M = {}

local setup_completed = false
local handlers = {}
local listeners = {}
local timers = {}
local callbacks = {}

local function call_cb(cb, reason, err, value)
	-- call_cb could be called from just about anywhere so we want to schedule on the event loop
	-- so we don't get randomly rekt further down the call stack
	vim.schedule(function()
		if err ~= nil then
			utils.error(reason .. ": " .. err)
			if cb ~= nil then
				local ok, result = pcall(cb, { ok = false, reason = reason, error = err, value = nil })
				if not ok then
					utils.error(result)
				end
			end
		else
			if cb ~= nil then
				local ok, result = pcall(cb, { ok = true, reason = nil, error = nil, value = value })
				if not ok then
					utils.error(result)
				end
			end
		end
	end)
end

local function clear_correlation(correlation_id)
	local timer = timers[correlation_id]
	if timer ~= nil and timer:is_active() then
		timer:stop()
		timer:close()
	end

	timers[correlation_id] = nil
	callbacks[correlation_id] = nil
end

function M.setup(opts)
	if setup_completed then
		return
	end

	config.setup(opts)

	M.next_id = 1
	M.session_name = nil
	M.socket_path = nil

	M.set_handler("testcommand", function(data)
		utils.info("in testcommand")
		utils.inspect(data)
		return { ret = "value" }
	end)

	M.set_handler("nvim_get_qflist", commands.nvim_get_qflist)
	M.set_handler("nvim_set_qflist", commands.nvim_set_qflist)
	M.set_handler("nvim_get_register", commands.nvim_get_register)

	M.add_listener("pong", events.pong)

	M.add_listener("command_success", function(data)
		local cb = callbacks[data.correlation_id]
		clear_correlation(data.correlation_id)
		call_cb(cb, "command_success", nil, data.value)
	end)

	M.add_listener("command_failure", function(data)
		local cb = callbacks[data.correlation_id]
		clear_correlation(data.correlation_id)
		call_cb(cb, "command_failure", "Pi extension exception with error: " .. data.error)
	end)

	setup_completed = true
end

function M.start()
	-- if already running, just dispatch focus instead
	if M.ready() then
		M.focus()
		return
	end

	M.session_name = utils.make_session_name()
	M.socket_path = utils.get_socket_dir() .. "/" .. M.session_name .. ".sock"
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
		utils.error(
			string.format(
				"'%s' is not a valid surface, options are %s. Defaulting to 'nvim'.",
				name,
				table.concat(vim.tbl_keys(default_surfaces), ", ")
			)
		)

		name = "nvim"
	end

	return require("simple-pi.surfaces." .. name)
end

function M.ready()
	return server.is_active()
end

local function ready_guard(cb)
	if not M.ready() then
		call_cb(cb, "error", "Not connected to Pi, run require('simple-pi').start()")
		return false
	end

	return true
end

function M.send(cb, type, name, data)
	if not ready_guard(cb) then
		return
	end

	local timer
	local correlation_id = M.next_id

	callbacks[M.next_id] = cb

	-- for commands we want to check for acks/nacks returning
	if type == "command" then
		timer = vim.uv.new_timer()
		assert(timer, "failed to create timer?")
		timers[correlation_id] = timer

		timer:start(1000, 0, function()
			-- if we're running we timed out

			-- close the timer
			timer:close()

			-- other cleanup
			clear_correlation(correlation_id)

			-- call callback
			call_cb(cb, "timeout", "command '" .. name .. "' timed out")
		end)
	end

	-- would've loved a uuid for the id but eh this is fine?
	server.send({ correlation_id = M.next_id, type = type, name = name, data = data })
	M.next_id = M.next_id + 1
end

function M.set_handler(command_name, func)
	handlers[command_name] = func
end

function M.add_listener(event_name, func)
	listeners[event_name] = listeners[event_name] or {}
	table.insert(listeners[event_name], func)
end

function M.on_message(msg)
	if msg.type == "command" then
		local handler = handlers[msg.name]

		if handler then
			local ok, value = pcall(handler, msg.data)
			if ok then
				M.send(nil, "event", "command_success", {
					correlation_id = msg.correlation_id,
					value = value,
				})
			else
				M.send(nil, "event", "command_failure", {
					correlation_id = msg.correlation_id,
					error = tostring(value),
				})
				utils.error("Command handler for '" .. msg.name .. "' failed: " .. value)
			end
		end
	elseif msg.type == "event" then
		for _, listener in ipairs(listeners[msg.name] or {}) do
			pcall(listener, msg.data)
		end
	end
end

function M.on_connect()
	local enabled_tools = {}

	local cb = function(d)
		if not d.ok then
			utils.raise("Failed to init Pi configuration over socket")
		end

		utils.info("Connected to Pi :D")
	end

	local all_tools = {
		"nvim_get_qflist",
		"nvim_set_qflist",
		"nvim_get_register",
	}

	for _, tool_name in ipairs(all_tools) do
		if not config.opts.tools.disable_all and config.opts.tools[tool_name].enabled then
			table.insert(enabled_tools, tool_name)
		end
	end

	M.send(cb, "command", "init", { enabled_tools = enabled_tools })
end

function M.on_disconnect()
	utils.info("Pi disconnected D:")

	if config.opts.close_on_disconnect then
		config.opts.surface.close()
	end
end

function M.ping()
	M.send(nil, "command", "ping", {})
end

function M.focus(cb)
	if not ready_guard(cb) then
		return
	end

	config.opts.surface.focus()
	call_cb(cb)
end

function M.close()
	if not ready_guard() then
		return false
	end

	return config.opts.surface.close()
end

function M.paste_line_reference(cb)
	if not ready_guard(cb) then
		return
	end

	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_get_current_buf()
	local line = vim.api.nvim_win_get_cursor(win)

	local buf_name = utils.get_buf_name(buf)

	if buf_name == nil then
		return call_cb(cb, "error", "Buffer is unnamed")
	end

	M.send(cb, "command", "append_text", {
		lines = { string.format("%s:%d", buf_name, line[1]) },
		as_paragraph = false,
	})
end

--
local function get_selection_span(retain_mode)
	local mode = vim.fn.mode()
	local buf = vim.api.nvim_get_current_buf()

	if (mode ~= "v") and (mode ~= "V") and (mode ~= "\22") then
		local win = vim.api.nvim_get_current_win()
		local line = vim.api.nvim_win_get_cursor(win)
		return buf, line[1], nil
	end

	-- unfortunately you need to exit visual mode for the < and > marks to update properly
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, false, true), "x", true)

	local buf = vim.api.nvim_get_current_buf()
	local start_mark = vim.api.nvim_buf_get_mark(buf, "<")
	local end_mark = vim.api.nvim_buf_get_mark(buf, ">")

	if retain_mode == true then
		vim.cmd("normal! gv")
	end

	local start_line = start_mark[1]
	local end_line = end_mark[1]

	return buf, start_line, end_line
end

function M.paste_range_reference(cb, opts)
	if not ready_guard(cb) then
		return
	end

	local buf, start_line, end_line = get_selection_span(opts ~= nil and opts.retain_mode or nil)
	local buf_name = utils.get_buf_name(buf)

	if buf_name == nil then
		return call_cb(cb, "error", "Buffer is unnamed")
	end

	M.send(cb, "command", "append_text", {
		lines = { string.format(end_line == nil and "%s:%d" or "%s:%d-%d", buf_name, start_line, end_line) },
		as_paragraph = false,
	})
end

function M.test(cb)
	if not ready_guard(cb) then
		return
	end

	M.send(cb, "command", "test", {})
end

function M.paste_selection(cb, opts)
	if not ready_guard(cb) then
		return
	end

	local buf, start_line, end_line = get_selection_span(opts ~= nil and opts.retain_mode or nil)
	local buf_name = utils.get_buf_name(buf)

	if buf_name == nil then
		return call_cb(cb, "error", "Buffer is unnamed")
	end

	local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line == nil and start_line or end_line, false)

	local with_header = {
		string.format(end_line == nil and "%s:%d" or "%s:%d-%d", buf_name, start_line, end_line),
		"```" .. vim.bo[buf].filetype,
	}

	vim.list_extend(with_header, lines)
	table.insert(with_header, "```")

	M.send(cb, "command", "append_text", { lines = with_header, as_paragraph = true })
end

return M
