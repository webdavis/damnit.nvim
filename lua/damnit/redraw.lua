local M = {}

local scratch = require("damnit.scratch")

local function oid_under_each_cursor(buf)
  local held = {}

  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local lnum = vim.api.nvim_win_get_cursor(win)[1]
    local row = scratch.row(buf, lnum)
    held[win] = { lnum = lnum, oid = row and row.oid }
  end

  return held
end

local function line_of(oid, rows, fallback)
  for index, row in ipairs(rows) do
    if row.oid == oid then
      return index
    end
  end

  return fallback
end

function M.keep_cursor(buf, paint)
  local held = oid_under_each_cursor(buf)

  paint()

  local rows = scratch.rows(buf)
  local count = vim.api.nvim_buf_line_count(buf)
  for win, was in pairs(held) do
    local target = was.oid and line_of(was.oid, rows, was.lnum) or was.lnum
    vim.api.nvim_win_set_cursor(win, { math.min(math.max(target, 1), count), 0 })
  end
end

return M
