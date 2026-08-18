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

	M.pipe:bind(path)
	if vim.uv.fs_chmod(path, tonumber("600", 8)) ~= true then
		vim.notify("Failed to chmod 600 socket file?", vim.log.levels.WARN)
	end

	M.pipe:listen(1, M.on_accept)
	M.pipe:unref()
end

function M.is_active()
	if M.client == nil then
		return false
	end

	return M.client:is_active()
end

function maybe_promote_pending()
	if M.pending_client == nil then
		return
	end

	local pending = M.pending_client
	M.pending_client = nil
	promote_client(pending)
end

function promote_client(client)
	M.client = client
	M.pending_client = nil

	local buffer = ""

	client:read_start(function(err, data)
		if err or data == nil or not data or data == "" then
			-- TODO: concern -- will we never call on_disconnect if client pipe is already closing?

			if not client:is_closing() then
				client:close(function()
					M.client = nil
					pcall(M.on_disconnect)
					maybe_promote_pending()
				end)
			end

			return
		end

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
				-- TODO: probably want to properly abandon if !ok
				if ok and M.on_message then
					M.on_message(msg)
				end
			end
		end
	end)

	M.on_connect()
end

function M.on_accept()
	local pending = vim.uv.new_pipe(false)
	assert(pending)

	M.pipe:accept(pending)

	if M.client ~= nil then
		-- immediately close if we have a healthy client
		if M.is_active() then
			pending:close()
			return
		end

		if M.pending_client ~= nil then
			-- already a pending client, just close this
			pending:close()
		else
			M.pending_client = pending
		end

		return
	end

	promote_client(pending)
end

function M.send(data)
	if not M.is_active() then
		return
	end

	M.client:write(vim.json.encode(data) .. "\n")
end

function M.stop()
	if M.path then
		os.remove(M.path)
	end
end

return M
