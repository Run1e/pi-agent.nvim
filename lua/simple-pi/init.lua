local commands = require("simple-pi.commands")
local config = require("simple-pi.config")
local events = require("simple-pi.events")
local server = require("simple-pi.server")
local utils = require("simple-pi.utils")

---@class simple_pi.CallbackResult
---@field ok boolean
---@field reason string? like "command_success", "command_failure", "timeout", "error"
---@field error string?
---@field value any?

---@alias simple_pi.PiCallback fun(result: simple_pi.CallbackResult)
---@alias simple_pi.CommandHandler fun(data: any): any?
---@alias simple_pi.EventListener fun(data: any)

---@class simple_pi.CommandSuccessData
---@field correlation_id number
---@field value any

---@class simple_pi.CommandFailureData
---@field correlation_id number
---@field error string

---@class simple_pi
local M = {}

local setup_completed = false

---@type table<string, simple_pi.CommandHandler>
local handlers = {}

---@type table<string, simple_pi.EventListener[]>
local listeners = {}

---@type table<number, any>
local timers = {}

---@type table<number, simple_pi.PiCallback>
local callbacks = {}

---@type string?
M.session_name = nil

---@type string?
M.socket_path = nil

---@type integer
M.next_id = 1

---@param cb simple_pi.PiCallback?
---@param reason string?
---@param err string?
---@param value any?
local function invoke_cb(cb, reason, err, value)
	-- call_cb could be called from just about anywhere so we want to schedule on the event loop
	-- so we don't get randomly rekt further down the call stack
	vim.schedule(function()
		if err ~= nil then
			err = tostring(err)
			utils.error((reason or "") .. ": " .. err)
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

---@param correlation_id number
local function clear_correlation(correlation_id)
	local timer = timers[correlation_id]
	if timer ~= nil and timer:is_active() then
		timer:stop()
		timer:close()
	end

	timers[correlation_id] = nil
	callbacks[correlation_id] = nil
end

---@param opts simple_pi.Opts?
function M.setup(opts)
	if setup_completed then
		return
	end

	config.setup(opts)

	M.next_id = 1
	M.session_name = nil
	M.socket_path = nil

	---@param data any
	local on_testcommand = function(data)
		utils.info("in testcommand")
		utils.inspect(data)
		return { ret = "value" }
	end

	M.set_handler("testcommand", on_testcommand)
	M.set_handler("nvim_get_qflist", commands.nvim_get_qflist)
	M.set_handler("nvim_set_qflist", commands.nvim_set_qflist)

	M.add_listener("pong", events.pong)

	---@param data simple_pi.CommandSuccessData
	local on_command_success = function(data)
		local cb = callbacks[data.correlation_id]
		clear_correlation(data.correlation_id)
		invoke_cb(cb, "command_success", nil, data.value)
	end

	M.add_listener("command_success", on_command_success)

	---@param data simple_pi.CommandFailureData
	local on_command_failure = function(data)
		local cb = callbacks[data.correlation_id]
		clear_correlation(data.correlation_id)
		local error_str = (data.error and #data.error) and data.error or "no error"
		invoke_cb(cb, "command_failure", "Pi extension exception with error: " .. error_str)
	end

	M.add_listener("command_failure", on_command_failure)

	setup_completed = true
end

function M.start()
	-- if already running, just dispatch focus instead
	if M.ready() then
		M.focus()
		return
	end

	local session_name = utils.make_session_name()
	M.session_name = session_name

	local socket_path = utils.get_socket_dir() .. "/" .. session_name .. ".sock"
	M.socket_path = socket_path

	server.start(socket_path, M.on_connect, M.on_disconnect, M.on_message)

	local opts = config.get_opts()
	opts.surface.open(M)

	if opts.focus_on_open then
		opts.surface.focus()
	end
end

function M.stop()
	server.stop()

	M.session_name = nil
	M.socket_path = nil
end

---@param name string
---@return simple_pi.Surface
function M.get_surface(name)
	---@type table<string, boolean>

	if not config.valid_surfaces[name] then
		utils.error(
			string.format(
				"'%s' is not a valid surface, options are %s. Defaulting to 'nvim'.",
				name,
				table.concat(vim.tbl_keys(config.valid_surfaces), ", ")
			)
		)

		name = "nvim"
	end

	return require("simple-pi.surfaces." .. name)
end

---@return boolean
function M.ready()
	return server.is_active()
end

---@param cb simple_pi.PiCallback?
---@return boolean
local function ready_guard(cb)
	if not M.ready() then
		invoke_cb(cb, "error", "Not connected to Pi, run require('simple-pi').start()")
		return false
	end

	return true
end

---@param cb simple_pi.PiCallback?
---@param type "command"|"event"
---@param name string
---@param data any
function M.send(cb, type, name, data)
	if not ready_guard(cb) then
		return
	end

	if type == "event" and cb ~= nil then
		utils.raise("events should not provide callbacks")
	end

	local timer
	local correlation_id = M.next_id

	-- for commands we want to check for acks/nacks returning
	if type == "command" then
		callbacks[M.next_id] = cb

		timer = vim.uv.new_timer()
		assert(timer, "failed to create timer?")
		timers[correlation_id] = timer

		timer:start(2500, 0, function()
			-- if we're running we timed out

			-- close the timer
			timer:close()

			-- other cleanup
			clear_correlation(correlation_id)

			-- call callback
			invoke_cb(cb, "timeout", "command '" .. name .. "' timed out")
		end)
	end

	-- would've loved a uuid for the id but eh this is fine?
	server.send({ correlation_id = M.next_id, type = type, name = name, data = data })
	M.next_id = M.next_id + 1
end

---@param command_name string
---@param func simple_pi.CommandHandler
function M.set_handler(command_name, func)
	handlers[command_name] = func
end

---@param event_name string
---@param func simple_pi.EventListener
function M.add_listener(event_name, func)
	listeners[event_name] = listeners[event_name] or {}
	table.insert(listeners[event_name], func)
end

---@param msg simple_pi.Message
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
				utils.error("Command handler for '" .. msg.name .. "' failed: " .. tostring(value))
			end
		end
	elseif msg.type == "event" then
		for _, listener in ipairs(listeners[msg.name] or {}) do
			local ok, value = pcall(listener, msg.data)
			if not ok then
				utils.error(string.format("Listener for event '%s' failed with error: %s", msg.name, tostring(value)))
			end
		end
	end
end

function M.on_connect()
	local enabled_tools = {}

	---@type simple_pi.PiCallback
	local cb = function(d)
		if not d.ok then
			utils.raise("Failed to init Pi configuration over socket")
		end

		utils.info("Connected to Pi :D")
	end

	local all_tools = {
		"nvim_get_qflist",
		"nvim_set_qflist",
	}

	local tools = config.get_opts().tools

	for _, tool_name in ipairs(all_tools) do
		if not tools.disable_all and tools[tool_name].enabled then
			table.insert(enabled_tools, tool_name)
		end
	end

	M.send(cb, "command", "init", { enabled_tools = enabled_tools })
end

function M.on_disconnect()
	utils.info("Pi disconnected D:")

	local opts = config.get_opts()

	if opts.close_on_disconnect then
		pcall(opts.surface.close)
	end
end

function M.ping()
	M.send(nil, "command", "ping", {})
end

---@param cb simple_pi.PiCallback?
function M.focus(cb)
	if not ready_guard(cb) then
		return
	end

	local ok, err = pcall(config.get_opts().surface.focus)

	if ok then
		invoke_cb(cb)
	else
		invoke_cb(cb, "error", err)
	end
end

---@param cb simple_pi.PiCallback?
function M.close(cb)
	if not ready_guard() then
		return false
	end

	local ok, err = pcall(config.get_opts().surface.close)

	if ok then
		invoke_cb(cb)
	else
		invoke_cb(cb, "error", err)
	end
end

---@param cb simple_pi.PiCallback?
function M.paste_line_reference(cb)
	if not ready_guard(cb) then
		return
	end

	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_get_current_buf()
	local line = vim.api.nvim_win_get_cursor(win)

	local buf_name = utils.get_buf_name(buf)

	if buf_name == nil then
		return invoke_cb(cb, "error", "Buffer is unnamed")
	end

	M.send(cb, "command", "append_text", {
		lines = { string.format("%s:%d", buf_name, line[1]) },
		as_paragraph = false,
	})
end

---@param retain_mode boolean?
---@return integer buf
---@return integer start_line
---@return integer? end_line
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

	local start_mark = vim.api.nvim_buf_get_mark(buf, "<")
	local end_mark = vim.api.nvim_buf_get_mark(buf, ">")

	if retain_mode == true then
		vim.cmd("normal! gv")
	end

	local start_line = start_mark[1]
	local end_line = end_mark[1]

	return buf, start_line, end_line
end

---@param cb simple_pi.PiCallback?
---@param opts { retain_mode: boolean? }?
function M.paste_range_reference(cb, opts)
	if not ready_guard(cb) then
		return
	end

	local ok, buf, start_line, end_line = pcall(get_selection_span, opts and opts.retain_mode)
	if not ok then
		invoke_cb(cb, "error", tostring(buf))
		return
	end

	local buf_name = utils.get_buf_name(buf)

	if buf_name == nil then
		return invoke_cb(cb, "error", "Buffer is unnamed")
	end

	M.send(cb, "command", "append_text", {
		lines = { string.format(end_line == nil and "%s:%d" or "%s:%d-%d", buf_name, start_line, end_line) },
		as_paragraph = false,
	})
end

---@param cb simple_pi.PiCallback?
function M.test(cb)
	if not ready_guard(cb) then
		return
	end

	M.send(cb, "command", "test", {})
end

---@param cb simple_pi.PiCallback?
---@param opts { retain_mode: boolean? }?
function M.paste_selection(cb, opts)
	if not ready_guard(cb) then
		return
	end

	local ok, buf, start_line, end_line = pcall(get_selection_span, opts and opts.retain_mode)
	if not ok then
		invoke_cb(cb, "error", tostring(buf))
		return
	end

	local buf_name = utils.get_buf_name(buf)

	if buf_name == nil then
		return invoke_cb(cb, "error", "Buffer is unnamed")
	end

	if end_line == nil then
		end_line = start_line
	end

	local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)

	local with_header = {
		string.format(end_line == start_line and "%s:%d" or "%s:%d-%d", buf_name, start_line, end_line),
		"```" .. (vim.bo[buf].filetype or ""),
	}

	vim.list_extend(with_header, lines)
	table.insert(with_header, "```")

	M.send(cb, "command", "append_text", { lines = with_header, as_paragraph = true })
end

---@param cb simple_pi.PiCallback?
function M.paste_qflist(cb)
	---@type string[]
	local lines = { "Neovim quickfix list (qflist):" }
	local qflines = commands.nvim_get_qflist(nil)
	vim.list_extend(lines, qflines)
	M.send(cb, "command", "append_text", { lines = lines, as_paragraph = true })
end

return M
