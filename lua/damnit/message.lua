local M = {}

M.PREFIX = "damnit.nvim: "

local ELLIPSIS = "…"

local HISTORY_UI = vim.api.nvim_create_namespace("damnit.message")

local function first_line(text)
  return (text:gsub("\n.*", ""))
end

local function cut_to(line, room)
  local kept = line
  while vim.fn.strdisplaywidth(kept .. ELLIPSIS) > room do
    kept = vim.fn.strcharpart(kept, 0, vim.fn.strchars(kept) - 1)
  end

  return kept .. ELLIPSIS
end

local function record_without_drawing(whole)
  vim.ui_attach(HISTORY_UI, { ext_messages = true }, function() end)
  vim.api.nvim_echo({ { whole } }, true, {})
  vim.ui_detach(HISTORY_UI)
end

function M.tell(level, text)
  local whole = M.PREFIX .. text
  local line = first_line(whole)
  local too_wide = vim.fn.strdisplaywidth(line) > vim.v.echospace

  if too_wide or line ~= whole then
    record_without_drawing(whole)
  end

  vim.notify(too_wide and cut_to(line, vim.v.echospace) or line, level)
end

function M.say(text)
  M.tell(vim.log.levels.INFO, text)
end

function M.warn(text)
  M.tell(vim.log.levels.WARN, text)
end

function M.fail(text)
  M.tell(vim.log.levels.ERROR, text)
end

function M.report(err)
  M.tell(err.kind == "missing" and vim.log.levels.ERROR or vim.log.levels.WARN, err.message)
end

return M
