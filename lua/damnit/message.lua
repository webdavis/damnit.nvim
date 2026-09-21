-- What the user is told, and who is speaking.
--
-- A sentence this plugin wrote is prefixed with its name. A sentence `dam` wrote
-- is passed through as dam wrote it. The prefix is the only way to tell them
-- apart in a notification, so it is written in exactly one place.

local M = {}

M.PREFIX = "damnit.nvim: "

--- An outcome the user asked for.
---@param text string
function M.say(text)
  vim.notify(M.PREFIX .. text, vim.log.levels.INFO)
end

--- A refusal or a failure the user can act on.
---@param text string
function M.warn(text)
  vim.notify(M.PREFIX .. text, vim.log.levels.WARN)
end

--- A configuration problem that makes the plugin unusable.
---@param text string
function M.fail(text)
  vim.notify(M.PREFIX .. text, vim.log.levels.ERROR)
end

--- One error table, at the level its kind deserves.
---
--- `plugin` marks a message this plugin composed, which is the only kind that
--- takes the prefix. Everything else is dam's own line.
---@param err damnit.Error
function M.report(err)
  local level = err.kind == "missing" and vim.log.levels.ERROR or vim.log.levels.WARN

  if err.plugin then
    return vim.notify(M.PREFIX .. err.message, level)
  end

  vim.notify(err.message, level)
end

return M
