local M = {}

local closed_sections_by_store = {}

function M.level(lnum)
  local kind = (vim.b.damnit_kinds or {})[lnum]

  if kind == "section" then
    return ">1"
  end

  if kind == "header" or kind == "blank" or kind == "empty" then
    return "0"
  end

  return "1"
end

M.EXPRESSION = "v:lua.require'damnit.folds'.level(v:lnum)"

local function recorded(win)
  local buf = vim.api.nvim_win_get_buf(win)

  return vim.b[buf].damnit_kinds or {}, vim.b[buf].damnit_sections or {}
end

function M.remember(key, win)
  closed_sections_by_store[key] = {}

  local kinds, sections = recorded(win)

  vim.api.nvim_win_call(win, function()
    for index, kind in ipairs(kinds) do
      if kind == "section" then
        closed_sections_by_store[key][sections[index]] = vim.fn.foldclosed(index) ~= -1
      end
    end
  end)
end

function M.apply(key, win)
  local wanted = closed_sections_by_store[key] or {}
  local kinds, sections = recorded(win)

  vim.api.nvim_win_call(win, function()
    for index, kind in ipairs(kinds) do
      if kind == "section" and wanted[sections[index]] then
        pcall(vim.cmd, index .. "foldclose")
      end
    end
  end)
end

return M
