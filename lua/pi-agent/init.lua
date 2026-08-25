local commands = require("pi-agent.commands")
local config = require("pi-agent.config")
local events = require("pi-agent.events")
local server = require("pi-agent.server")
local utils = require("pi-agent.utils")

---@class pi_agent.CallbackResult
---@field ok boolean
---@field reason ("command_success"|"command_failure"|"timeout"|"error")?
---@field error string?
---@field value any?

---@alias pi_agent.Callback fun(result: pi_agent.CallbackResult)
---@alias pi_agent.CommandHandler fun(pi: pi_agent.Pi, data: any): any?
---@alias pi_agent.EventListener fun(pi: pi_agent.Pi, data: any)
---@alias pi_agent.PiEventListener fun(event: any): any?

---@class pi_agent.CommandSuccessData
---@field correlation_id number
---@field value any

---@class pi_agent.CommandFailureData
---@field correlation_id number
---@field error string

---@class pi_agent.Pi
local Pi = {}

Pi.setup_completed = false

---@type table<string, pi_agent.CommandHandler>
Pi.handlers = {}

---@type table<string, pi_agent.EventListener[]>
Pi.listeners = {}

---@type table<number, uv.uv_timer_t>
Pi.timers = {}

---@type table<number, pi_agent.Callback>
Pi.callbacks = {}

---@type pi_agent.Server?
Pi.server = nil

---@type string?
Pi.session_name = nil

---@type string?
Pi.socket_path = nil

---@type integer
Pi.next_id = 1

---@type string[]
Pi.pi_events = {}

---@type string[]
Pi.pi_events_blocking = {}

---@type table<string, pi_agent.PiEventListener[]>
Pi.pi_event_listeners = {}

---@type table<string, pi_agent.PiEventListener>
Pi.pi_event_listeners_blocking = {}

---@param cb pi_agent.Callback?
---@param reason string?
---@param err string?
---@param value any?
function Pi.invoke_cb(cb, reason, err, value)
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
function Pi.clear_correlation(correlation_id)
	local timer = Pi.timers[correlation_id]
	if timer ~= nil then
		timer:stop()
		timer:close()
	end

	Pi.timers[correlation_id] = nil
	Pi.callbacks[correlation_id] = nil
end

---@param opts pi_agent.config.Opts?
function Pi.setup(opts)
	if Pi.setup_completed then
		return
	end

	config.setup(opts)

	config.get_opts().surface.setup()

	Pi.next_id = 1
	Pi.session_name = nil
	Pi.socket_path = nil

	Pi.set_handler("nvim_get_qflist", commands.nvim_get_qflist)
	Pi.set_handler("nvim_set_qflist", commands.nvim_set_qflist)

	Pi.add_listener("pong", events.pong)
	Pi.add_listener("command_success", events.on_command_success)
	Pi.add_listener("command_failure", events.on_command_failure)
	Pi.add_listener("pi_event", events.pi_event)

	Pi.setup_completed = true
end

function Pi.start()
	-- if already running, just dispatch focus instead
	if Pi.ready() then
		Pi.focus()
		return
	end

	local session_name = utils.make_session_name()
	Pi.session_name = session_name

	local socket_path = utils.get_socket_dir() .. "/" .. session_name .. ".sock"
	Pi.socket_path = socket_path

	if Pi.server ~= nil then
		Pi.server:stop()
	end

	Pi.server = server.new(socket_path, Pi.on_connect, Pi.on_disconnect, Pi.on_message)

	local opts = config.get_opts()
	opts.surface.open(Pi)

	if opts.focus_on_open then
		opts.surface.focus()
	end
end

function Pi.stop()
	if Pi.server ~= nil then
		Pi.server:stop()
	end

	Pi.server = nil
	Pi.session_name = nil
	Pi.socket_path = nil
end

---@param name string
---@return pi_agent.Surface
function Pi.get_surface(name)
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

	return require("pi-agent.surfaces." .. name)
end

---@return boolean
function Pi.ready()
	return Pi.server ~= nil and Pi.server:is_active()
end

---@param cb pi_agent.Callback?
---@return boolean
local function ready_guard(cb)
	if not Pi.ready() then
		Pi.invoke_cb(cb, "error", "Not connected to pi, run require('pi-agent').start()")
		return false
	end

	return true
end

---@param cb pi_agent.Callback?
---@param type "command"|"event"
---@param name string
---@param data any
function Pi.send(cb, type, name, data)
	if not ready_guard(cb) then
		return
	end

	if type == "event" and cb ~= nil then
		utils.raise("Events should not provide callbacks")
	end

	local timer
	local correlation_id = Pi.next_id

	-- for commands we want to check for acks/nacks returning
	if type == "command" and cb ~= nil then
		-- noop if cb == nil
		Pi.callbacks[Pi.next_id] = cb

		timer = vim.uv.new_timer()
		assert(timer, "failed to create timer?")
		Pi.timers[correlation_id] = timer

		timer:start(2500, 0, function()
			Pi.clear_correlation(correlation_id)
			Pi.invoke_cb(cb, "timeout", "command '" .. name .. "' timed out")
		end)
	end

	-- would've loved a uuid for the id but eh this is fine?
	Pi.server:send({ correlation_id = correlation_id, type = type, name = name, data = data })
	Pi.next_id = Pi.next_id + 1
end

---@param command_name string
---@param func pi_agent.CommandHandler
function Pi.set_handler(command_name, func)
	Pi.handlers[command_name] = func
end

---@param event_name string
---@param func pi_agent.EventListener
function Pi.add_listener(event_name, func)
	Pi.listeners[event_name] = Pi.listeners[event_name] or {}
	table.insert(Pi.listeners[event_name], func)
end

---@param msg pi_agent.Message
function Pi.on_message(msg)
	if msg.type == "command" then
		local handler = Pi.handlers[msg.name]

		if handler then
			local ok, value = pcall(handler, Pi, msg.data)
			if ok then
				Pi.send(nil, "event", "command_success", {
					correlation_id = msg.correlation_id,
					value = value,
				})
			else
				Pi.send(nil, "event", "command_failure", {
					correlation_id = msg.correlation_id,
					error = tostring(value),
				})
				utils.error("Command handler for '" .. msg.name .. "' failed: " .. tostring(value))
			end
		end
	elseif msg.type == "event" then
		for _, listener in ipairs(Pi.listeners[msg.name] or {}) do
			local ok, value = pcall(listener, Pi, msg.data)
			if not ok then
				utils.error(string.format("Listener for event '%s' failed with error: %s", msg.name, tostring(value)))
			end
		end
	end
end

---@param event_name string
---@param listener pi_agent.PiEventListener
---@param blocking boolean?
local function _on(event_name, listener, blocking)
	if blocking == true then
		-- can't add a blocking listener if there already is one
		if utils.list_contains(Pi.pi_events_blocking, event_name) then
			utils.raise(string.format("pi event '%s' already has a blocking listener added"))
		end

		-- if blocking, remove from non-blocking if exists
		if utils.list_contains(Pi.pi_events, event_name) then
			utils.list_remove(Pi.pi_events, event_name)
		end

		-- and add to blocking list if it doesn't
		if not utils.list_contains(Pi.pi_events_blocking, event_name) then
			table.insert(Pi.pi_events_blocking, event_name)
			if Pi.ready() then
				Pi.send(nil, "event", "register_event_interest", { event_name = event_name, blocking = true })
			end
		end

		Pi.pi_event_listeners_blocking[event_name] = listener
	else
		-- only add if it exists in neither list so far
		if not utils.list_contains(Pi.pi_events_blocking, event_name) then
			if not utils.list_contains(Pi.pi_events, event_name) then
				table.insert(Pi.pi_events, event_name)
				if Pi.ready() then
					Pi.send(nil, "event", "register_event_interest", { event_name = event_name, blocking = false })
				end
			end
		end

		Pi.pi_event_listeners[event_name] = Pi.pi_event_listeners[event_name] or {}
		table.insert(Pi.pi_event_listeners[event_name], listener)
	end
end

---@param event_name string
---@param listener pi_agent.PiEventListener
function Pi.on(event_name, listener)
	_on(event_name, listener, false)
end

---@param event_name string
---@param listener pi_agent.PiEventListener
function Pi.on_blocking(event_name, listener)
	_on(event_name, listener, true)
end

function Pi.on_connect()
	local enabled_tools = {}

	---@type pi_agent.Callback
	local cb = function(d)
		if not d.ok then
			utils.raise("Failed to init pi configuration over socket")
		end

		utils.info("Connected to pi :D")
	end

	local tools = config.get_opts().tools

	for tool_name, tool_config in pairs(tools) do
		-- TODO: fix this I hate this a lot much hate
		if tool_name == "disable_all" then
			goto continue
		end

		if not tools.disable_all and tool_config.enabled then
			table.insert(enabled_tools, tool_name)
		end
		::continue::
	end

	local init_data = {
		enabled_tools = enabled_tools,
		events = Pi.pi_events,
		events_blocking = Pi.pi_events_blocking,
	}

	Pi.send(cb, "command", "init", init_data)
end

function Pi.on_disconnect()
	utils.info("pi disconnected D:")

	local opts = config.get_opts()

	if opts.close_on_disconnect then
		pcall(opts.surface.close)
	end
end

function Pi.ping(cb)
	Pi.send(cb, "command", "ping", {})
end

---@param cb pi_agent.Callback?
function Pi.focus(cb)
	if not ready_guard(cb) then
		return
	end

	local ok, err = pcall(config.get_opts().surface.focus)

	if ok then
		Pi.invoke_cb(cb)
	else
		Pi.invoke_cb(cb, "error", err)
	end
end

---@param cb pi_agent.Callback?
function Pi.close(cb)
	if not ready_guard(cb) then
		return
	end

	local ok, err = pcall(config.get_opts().surface.close)

	if ok then
		Pi.invoke_cb(cb)
	else
		Pi.invoke_cb(cb, "error", err)
	end
end

---@param cb pi_agent.Callback?
function Pi.paste_line_reference(cb)
	if not ready_guard(cb) then
		return
	end

	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_get_current_buf()
	local line = vim.api.nvim_win_get_cursor(win)

	local buf_name = utils.get_buf_name(buf)

	if buf_name == nil then
		return Pi.invoke_cb(cb, "error", "Buffer is unnamed")
	end

	Pi.send(cb, "command", "append_text", {
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

---@param cb pi_agent.Callback?
---@param opts { retain_mode: boolean? }?
function Pi.paste_range_reference(cb, opts)
	if not ready_guard(cb) then
		return
	end

	local ok, buf, start_line, end_line = pcall(get_selection_span, opts and opts.retain_mode)
	if not ok then
		Pi.invoke_cb(cb, "error", tostring(buf))
		return
	end

	local buf_name = utils.get_buf_name(buf)

	if buf_name == nil then
		return Pi.invoke_cb(cb, "error", "Buffer is unnamed")
	end

	Pi.send(cb, "command", "append_text", {
		lines = { string.format(end_line == nil and "%s:%d" or "%s:%d-%d", buf_name, start_line, end_line) },
		as_paragraph = false,
	})
end

---@param cb pi_agent.Callback?
---@param opts { retain_mode: boolean? }?
function Pi.paste_selection(cb, opts)
	if not ready_guard(cb) then
		return
	end

	local ok, buf, start_line, end_line = pcall(get_selection_span, opts and opts.retain_mode)
	if not ok then
		Pi.invoke_cb(cb, "error", tostring(buf))
		return
	end

	local buf_name = utils.get_buf_name(buf)

	if buf_name == nil then
		return Pi.invoke_cb(cb, "error", "Buffer is unnamed")
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

	Pi.send(cb, "command", "append_text", { lines = with_header, as_paragraph = true })
end

---@param cb pi_agent.Callback?
function Pi.paste_qflist(cb)
	---@type string[]
	local lines = { "Neovim quickfix list (qflist):" }
	local qflines = commands.nvim_get_qflist(nil)
	vim.list_extend(lines, qflines)
	Pi.send(cb, "command", "append_text", { lines = lines, as_paragraph = true })
end

return Pi
