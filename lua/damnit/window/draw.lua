local M = {}

local diff = require("damnit.render.diff")
local entries = require("damnit.window.entries")
local folds = require("damnit.folds")
local redraw = require("damnit.redraw")
local render = require("damnit.render")
local scratch = require("damnit.scratch")

local function keep_the_cursor_in_its_section(buf, win, place)
  local row = scratch.row(buf, vim.api.nvim_win_get_cursor(win)[1])
  if not place or (row and row.section) == place.section then
    return
  end

  local line = entries.line_of(buf, place.section, place.nth)
  if line then
    vim.api.nvim_win_set_cursor(win, { line, 0 })
  end
end

function M.draw(buf, win, key, model, lines)
  local place = win and entries.place(buf, vim.api.nvim_win_get_cursor(win)[1])

  if win then
    folds.remember(key, win)
  end

  redraw.keep_cursor(buf, function()
    render.draw(buf, lines)
    diff.apply(buf, key, model)
  end)

  if win then
    keep_the_cursor_in_its_section(buf, win, place)
    folds.apply(key, win)
  end
end

return M
