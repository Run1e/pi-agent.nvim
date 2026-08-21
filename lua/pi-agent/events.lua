local utils = require("pi-agent.utils")

local M = {}

---@param data any
function M.pong(pi, data)
	utils.info("pong!!!!")
end

---@param data pi_agent.CommandSuccessData
function M.on_command_success(pi, data)
	local cb = pi.callbacks[data.correlation_id]
	pi.clear_correlation(data.correlation_id)
	pi.invoke_cb(cb, "command_success", nil, data.value)
end

---@param data pi_agent.CommandFailureData
function M.on_command_failure(pi, data)
	local cb = pi.callbacks[data.correlation_id]
	pi.clear_correlation(data.correlation_id)
	local error_str = (data.error and #data.error) and data.error or "no error"
	pi.invoke_cb(cb, "command_failure", "Pi extension exception with error: " .. error_str)
end

function M.pi_event(pi, event)
	local non_blocking_listeners = pi.pi_event_listeners[event.name] or {}
	local blocking_listener = pi.pi_event_listeners_blocking[event.name]

	for _, listener in ipairs(non_blocking_listeners) do
		local ok, err = pcall(listener, event.event)
		if not ok then
			utils.error(string.format("non-blocking pi listener for '%s' failed with error: %s", event.name, err))
		end
	end

	if blocking_listener ~= nil then
		local ok, result = pcall(blocking_listener, event.event)
		if not ok then
			utils.error(
				string.format("blocking pi listener for '%s' failed with error: %s", event.name, tostring(result))
			)
			pi.send(
				nil,
				"event",
				"pi_event_response",
				{ correlation_id = event.correlation_id, result = nil, error = tostring(result) }
			)
		else
			pi.send(
				nil,
				"event",
				"pi_event_response",
				{ correlation_id = event.correlation_id, result = result, error = nil }
			)
		end
	end
end

function M.register_event_interest(pi, event) end

return M
