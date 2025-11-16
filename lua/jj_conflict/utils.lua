local M = {}

--local api = vim.api
--local fn = vim.fn

--- Wrapper for [vim.notify]
---@param msg string|string[]
---@param level "error" | "trace" | "debug" | "info" | "warn"
---@param once boolean?
function M.notify(msg, level, once)
  if type(msg) == 'table' then msg = table.concat(msg, '\n') end
  local lvl = vim.log.levels[level:upper()] or vim.log.levels.INFO
  local opts = { title = 'Git conflict' }
  if once then return vim.notify_once(msg, lvl, opts) end
  vim.notify(msg, lvl, opts)
end
  

return M
