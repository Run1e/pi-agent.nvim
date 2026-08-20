local utils = require("simple-pi.utils")

local M = {}

M.pipe = nil
M.client = nil
M.pending_client = nil

M.path = nil
M.on_connect = nil
M.on_disconnect = nil

function M.start(path, on_connect, on_disconnect, on_message)
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

function M.is_active()
	if M.client == nil then
		return false
	end

	return M.client:is_active()
end

function M.send(data)
	if not M.is_active() then
		return
	end

	local ok, data = pcall(vim.json.encode, data)
	if not ok then
		utils.error("Failed to encode json data")
		return
	end

	M.client:write(data .. "\n", function(err)
		-- close socket on write error
		if err then
			M.close()
		end
	end)
end

function M.close(inhibit_promote)
	if M.client == nil then
		return
	end

	M.client:close(function()
		pcall(M.on_disconnect)
		if inhibit_promote ~= true then
			M.maybe_promote_pending()
		end
	end)
end

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

					if not ok then
						vim.schedule(function()
							utils.error("Bad JSON from client, closing")
							M.close()
						end)
					elseif M.on_message then
						vim.schedule(function()
							M.on_message(msg)
						end)
					end
				end
			end
		else
			-- handle eof (disconnect)
			M.close()
		end
	end)

	vim.schedule(function()
		M.on_connect()
	end)
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
		error("[simple-pi] Failed accepting new client connection")
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
