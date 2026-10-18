local M = {}

local function oid_under_each_cursor(buf)
  local oids = vim.b[buf].damnit_oids or {}
  local held = {}

  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local lnum = vim.api.nvim_win_get_cursor(win)[1]
    held[win] = { lnum = lnum, oid = oids[lnum] or nil }
  end

  return held
end

local function line_of(oid, oids, fallback)
  for index, each in ipairs(oids) do
    if each == oid then
      return index
    end
  end

  return fallback
end

function M.keep_cursor(buf, oids, paint)
  local held = oid_under_each_cursor(buf)

  paint()
  vim.b[buf].damnit_oids = oids

  local count = vim.api.nvim_buf_line_count(buf)
  for win, was in pairs(held) do
    local target = was.oid and line_of(was.oid, oids, was.lnum) or was.lnum
    vim.api.nvim_win_set_cursor(win, { math.min(math.max(target, 1), count), 0 })
  end
end

return M
