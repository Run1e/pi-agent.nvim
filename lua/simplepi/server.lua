local M = {}

M.pipe = nil
M.client = nil
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
	M.pipe:listen(1, M.on_accept)
end

function M.is_active()
	if M.client == nil then
		return false
	end

	return M.client:is_active()
end

function M.on_accept()
	M.client = vim.uv.new_pipe(false)
	M.pipe:accept(M.client)

	local buffer = ""

	M.client:read_start(function(err, data)
		if err or data == nil or not data or data == "" then
			-- TODO: concern -- will we never call on_disconnect if client pipe is already closing?
			if not M.client:is_closing() then
				M.client:close(function()
					M.client = nil
					M.on_disconnect()
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

function M.send(data)
	if M.client == nil then
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
