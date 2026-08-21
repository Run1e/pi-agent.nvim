local utils = require("simple-pi.utils")

local M = {}

---@class simple_pi.Message
---@field correlation_id number
---@field type "command"|"event"
---@field name string
---@field data any

---@type uv.uv_pipe_t?
M.pipe = nil

---@type uv.uv_pipe_t?
M.client = nil

---@type uv.uv_pipe_t?
M.pending_client = nil

---@type string?
M.path = nil

---@type fun()?
M.on_connect = nil

---@type fun()?
M.on_disconnect = nil

---@type fun(msg: simple_pi.Message)?
M.on_message = nil

---@param path string
---@param on_connect fun()
---@param on_disconnect fun()
---@param on_message fun(msg: simple_pi.Message)
function M.start(path, on_connect, on_disconnect, on_message)
	if M.pipe ~= nil then
		utils.raise("Server is already running, don't call .start again")
	end

	M.path = path

	M.on_connect = on_connect
	M.on_disconnect = on_disconnect
	M.on_message = on_message

	os.remove(path)

	M.pipe = vim.uv.new_pipe(false)

	if M.pipe:bind(path) ~= 0 then
		utils.raise("Failed to bind to socket")
	end

	if vim.uv.fs_chmod(path, tonumber("600", 8)) ~= true then
		utils.warn("Failed to chmod 600 socket file?")
	end

	if M.pipe:listen(1, M.on_accept) ~= 0 then
		utils.raise("Failed to start socket listener")
	end

	M.pipe:unref()
end

---@return boolean
function M.is_active()
	if M.client == nil then
		return false
	end

	return M.client:is_active() == true
end

---@param data table
function M.send(data)
	if not M.is_active() then
		return
	end

	local ok, encoded = pcall(vim.json.encode, data)
	if not ok then
		utils.error("Failed to encode json data")
		return
	end

	M.client:write(encoded .. "\n", function(err)
		-- close socket on write error
		if err then
			M.close()
		end
	end)
end

---@param inhibit_promote boolean?
function M.close(inhibit_promote)
	if M.client == nil then
		return
	end

	M.client:close(function()
		vim.schedule(assert(M.on_disconnect))
		if inhibit_promote ~= true then
			M.maybe_promote_pending()
		end
	end)
end

---@param client uv.uv_pipe_t
function M.promote_client(client)
	M.client = client
	M.pending_client = nil

	local buffer = ""

	client:read_start(function(err, data)
		if err then
			-- handle read error
			M.close()
		elseif data then
			-- handle data
			buffer = buffer .. data

			local nl
			while true do
				nl = buffer:find("\n", 1, true)
				if not nl then
					break
				end
				local line = buffer:sub(1, nl - 1)
				buffer = buffer:sub(nl + 1)
				if line ~= "" then
					local ok, msg = pcall(vim.json.decode, line)

					-- schedule out from the read hot loop
					vim.schedule(function()
						if not ok then
							utils.error("Bad JSON from client, closing")
							M.close()
						elseif M.on_message then
							M.on_message(msg)
						end
					end)
				end
			end
		else
			-- handle eof (disconnect)
			M.close()
		end
	end)

	vim.schedule(assert(M.on_connect))
end

function M.maybe_promote_pending()
	if M.pending_client == nil then
		return
	end

	if M.client and M.client:is_active() then
		M.pending_client:close()
		M.pending_client = nil
		return
	end

	M.promote_client(M.pending_client)
end

function M.on_accept()
	local pending = vim.uv.new_pipe(false)
	assert(pending)

	if M.pipe:accept(pending) ~= 0 then
		utils.raise("Failed accepting new client connection")
	end

	if M.pending_client == nil then
		-- pending slot open, set it
		M.pending_client = pending
	else
		-- pending isn't even open, reject connection
		pending:close()
		return
	end

	M.maybe_promote_pending()
end

function M.stop()
	if M.pending_client then
		M.pending_client:close()
		M.pending_client = nil
	end

	if M.client then
		M.close(true)
		M.client = nil
	end

	if M.pipe then
		local path = M.path
		M.path = nil
		M.pipe:close(function()
			if path then
				os.remove(path)
			end
		end)
		M.pipe = nil
	end
end

return M
