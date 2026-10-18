local M = {}

local ELLIPSIS = "…"

local function history_lines()
  return vim.split(vim.api.nvim_exec2("messages", { output = true }).output, "\n", { plain = true })
end

function M.whole_text(notification)
  if not vim.endswith(notification, ELLIPSIS) then
    return notification
  end

  local stem = notification:sub(1, -#ELLIPSIS - 1)
  local found = notification
  for _, line in ipairs(history_lines()) do
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
