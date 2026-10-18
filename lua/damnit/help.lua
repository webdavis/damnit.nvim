local M = {}

local HELP_CLOSE_KEYS = { "q", "g?", "<Esc>" }

function M.open(_, filetype)
  local rows = {}
  for _, map in ipairs(require("damnit.keys").MAPS[filetype] or {}) do
    rows[#rows + 1] = ("  %-8s %s"):format(map.lhs, map.desc)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rows)
  vim.bo[buf].modifiable = false

  local width = 0
  for _, row in ipairs(rows) do
    width = math.max(width, #row)
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - #rows) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width + 2,
    height = #rows,
    style = "minimal",
    border = "rounded",
  })

  for _, key in ipairs(HELP_CLOSE_KEYS) do
    vim.keymap.set("n", key, function()
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf, nowait = true })
  end
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once = true,
    callback = function()
      pcall(vim.api.nvim_win_close, win, true)
    end,
  })
end

return M
