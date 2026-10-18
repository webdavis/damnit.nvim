local M = {}

M.PREFIX = "damnit.nvim: "

local ELLIPSIS = "…"

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

function M.tell(level, text)
  local whole = M.PREFIX .. text
  local line = first_line(whole)

  if vim.fn.strdisplaywidth(line) > vim.v.echospace then
    vim.api.nvim_echo({ { whole } }, true, {})
    vim.api.nvim_echo({ { "" } }, false, {})
    vim.cmd("redraw")
    line = cut_to(line, vim.v.echospace)
  end

  vim.notify(line, level)
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
