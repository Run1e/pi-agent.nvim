local utils = require("pi-agent.utils")

local M = {}

---@param data any
function M.pong(data)
	utils.info("pong!!!!")
end

return M
