local M = {}

local color = require('jj_conflict.colors')
local utils = require('jj_conflict.utils')

local fn = vim.fn
local api = vim.api
local fmt = string.format
local map = vim.keymap.set
--todo():local job = utils.job


--- @class ConflictHighlights
--- @field current string
--- @field incoming string
--- @field ancestor string?

--- @class JJConflictUserConfig
--- @field highlights? ConflictHighlights
--- @field debug? boolean

---@param user_config JJConflictUserConfig
function M.setup(user_config)
  if fn.executable('jj') <= 0 then
    return vim.schedule(
      function()
        utils.notify('You need to have jj installed in order to use this plugin', 'error', true)
      end
    )

  end
end

return M

