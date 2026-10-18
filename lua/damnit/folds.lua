local M = {}

local scratch = require("damnit.scratch")

local closed_sections_by_store = {}

function M.level(lnum)
  local row = scratch.row(vim.api.nvim_get_current_buf(), lnum)
  local kind = row and row.kind

  if kind == "section" then
    return ">1"
  end

  if kind == "header" or kind == "blank" or kind == "empty" then
    return "0"
  end

  return "1"
end

M.EXPRESSION = "v:lua.require'damnit.folds'.level(v:lnum)"

local function headings(win)
  local found = {}

  for lnum, row in ipairs(scratch.rows(vim.api.nvim_win_get_buf(win))) do
    if row.kind == "section" then
      found[lnum] = row.section
    end
  end

  return found
end

function M.remember(key, win)
  closed_sections_by_store[key] = {}

  local sections = headings(win)

  vim.api.nvim_win_call(win, function()
    for lnum, section in pairs(sections) do
      closed_sections_by_store[key][section] = vim.fn.foldclosed(lnum) ~= -1
    end
  end)
end

function M.apply(key, win)
  local wanted = closed_sections_by_store[key] or {}
  local sections = headings(win)

  vim.api.nvim_win_call(win, function()
    for lnum, section in pairs(sections) do
      if wanted[section] then
        pcall(vim.cmd, lnum .. "foldclose")
      end
    end
  end)
end

return M
