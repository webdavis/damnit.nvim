local SHARED_BY_EVERY_DOFILE = "damnit.tests.said"

if package.loaded[SHARED_BY_EVERY_DOFILE] then
  return package.loaded[SHARED_BY_EVERY_DOFILE]
end

local M = {}
package.loaded[SHARED_BY_EVERY_DOFILE] = M

local ELLIPSIS = "…"

local recorders = {}

local function kept()
  local whole = {}
  for _, say in ipairs(recorders) do
    vim.list_extend(whole, say.kept())
  end

  return whole
end

function M.recorder()
  local lines, levels = {}, {}
  local say = require("damnit.message").new(function(text, level)
    lines[#lines + 1] = text
    levels[#lines] = level
  end)
  recorders[#recorders + 1] = say

  return say, lines, levels
end

function M.whole_text(notification)
  if not vim.endswith(notification, ELLIPSIS) then
    return notification
  end

  local stem = notification:sub(1, -#ELLIPSIS - 1)
  local found = notification
  for _, line in ipairs(kept()) do
    if vim.startswith(line, stem) then
      found = line
    end
  end

  return found
end

function M.whole(notification, text)
  return M.whole_text(notification) == text
end

function M.any(notifications, text)
  for _, notification in ipairs(notifications) do
    if M.whole(notification, text) then
      return true
    end
  end

  return false
end

return M
