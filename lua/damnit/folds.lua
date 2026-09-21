-- One fold per section of the status window, and what the user left closed.
--
-- The fold expression and the two halves of remembering read the same two
-- buffer variables the renderer records, so a section that moved between two
-- reads is still the section the user closed.

local M = {}

--- The sections a store's window has closed, remembered for the session.
---@type table<string, table<string, boolean>>
local closed = {}

--- The fold level of one line, read off the kinds the renderer recorded.
---@param lnum integer
---@return string
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

--- The fold expression a status window is configured with.
M.EXPRESSION = "v:lua.require'damnit.folds'.level(v:lnum)"

---@param win integer
---@return table kinds, table sections
local function recorded(win)
  local buf = vim.api.nvim_win_get_buf(win)

  return vim.b[buf].damnit_kinds or {}, vim.b[buf].damnit_sections or {}
end

--- Record which sections are closed before the window is redrawn.
---@param key string
---@param win integer
function M.remember(key, win)
  closed[key] = {}

  local kinds, sections = recorded(win)

  vim.api.nvim_win_call(win, function()
    for index, kind in ipairs(kinds) do
      if kind == "section" then
        closed[key][sections[index]] = vim.fn.foldclosed(index) ~= -1
      end
    end
  end)
end

--- Close again what was closed before the redraw.
---@param key string
---@param win integer
function M.apply(key, win)
  local wanted = closed[key] or {}
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
