local utils = require("pi-agent.utils")

---@class pi_agent.Server
---@field path string
---@field pipe uv.uv_pipe_t
---@field client uv.uv_pipe_t?
---@field pending_client uv.uv_pipe_t?
---@field on_connect fun()
---@field on_disconnect fun()
---@field on_message fun(msg: pi_agent.Message)
local Server = {}
Server.__index = Server

---@class pi_agent.Message
---@field correlation_id number
---@field type "command"|"event"
---@field name string
---@field data any

---@param path string
---@param on_connect fun()
---@param on_disconnect fun()
---@param on_message fun(msg: pi_agent.Message)
---@return pi_agent.Server
function Server.new(path, on_connect, on_disconnect, on_message)
	os.remove(path)

	local pipe = vim.uv.new_pipe(false)

	if pipe == nil then
		utils.raise("Pipe returned nil")
	end

	local self = setmetatable({
		path = path,
		pipe = pipe,
		on_connect = on_connect,
		on_disconnect = on_disconnect,
		on_message = on_message,
	}, Server)

	if self.pipe:bind(path) ~= 0 then
		utils.raise("Failed to bind to socket")
	end

	if vim.uv.fs_chmod(path, tonumber("600", 8)) ~= true then
		utils.warn("Failed to chmod 600 socket file?")
	end

	if self.pipe:listen(1, function()
		self:on_accept()
	end) ~= 0 then
		utils.raise("Failed to start socket listener")
	end

	self.pipe:unref()

	return self
end

---@return boolean
function Server:is_active()
	if self.client == nil then
		return false
	end

	return self.client:is_active() == true
end

---@param data table
function Server:send(data)
	if not self:is_active() then
		return
	end

	local ok, encoded = pcall(vim.json.encode, data)
	if not ok then
		utils.error("Failed to encode json data")
		return
	end

	self.client:write(encoded .. "\n", function(err)
		-- close socket on write error
		if err then
			self:close()
		end
	end)
end

---@param inhibit_promote boolean?
function Server:close(inhibit_promote)
	if self.client == nil then
		return
	end

	self.client:close(function()
		if self.on_disconnect then
			vim.schedule(self.on_disconnect)
		end

		if inhibit_promote ~= true then
			self:maybe_promote_pending()
		end
	end)
end

---@param client uv.uv_pipe_t
function Server:promote_client(client)
	self.client = client
	self.pending_client = nil

	local buffer = ""

	client:read_start(function(err, data)
		if err then
			-- handle read error
			self:close()
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
							self:close()
						elseif self.on_message then
							self.on_message(msg)
						end
					end)
				end
			end
		else
			-- handle eof (disconnect)
			self:close()
		end
	end)

	if self.on_connect then
		vim.schedule(self.on_connect)
	end
end

function Server:maybe_promote_pending()
	if self.pending_client == nil then
		return
	end

	if self.client and self.client:is_active() then
		self.pending_client:close()
		self.pending_client = nil
		return
	end

	self:promote_client(self.pending_client)
end

function Server:on_accept()
	local pending = vim.uv.new_pipe(false)
	assert(pending)

	if self.pipe:accept(pending) ~= 0 then
		utils.raise("Failed accepting new client connection")
	end

	if self.pending_client == nil then
		-- pending slot open, set it
		self.pending_client = pending
	else
		-- pending isn't even open, reject connection
		pending:close()
		return
	end

	self:maybe_promote_pending()
end

function Server:stop()
	if self.pending_client and not self.pending_client:is_closing() then
		self.pending_client:close()
	end

	if self.client and not self.client:is_closing() then
		self:close(true)
	end

	if self.pipe and not self.pipe:is_closing() then
		self.pipe:close(function()
			if self.path then
				os.remove(self.path)
			end
		end)
	end
end

return Server
