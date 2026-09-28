local M = {}

local folds = require("damnit.folds")

local function configure(win)
  vim.wo[win].foldmethod = "expr"
  vim.wo[win].foldexpr = folds.EXPRESSION
  vim.wo[win].foldlevel = 99
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
end

local function open_split(buf)
  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_height(0, math.max(math.floor(vim.o.lines / 3), 10))
end

local function open_float(buf)
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.7)

  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.win then
    snacks.win({ buf = buf, width = width, height = height, border = "rounded" })

    return
  end

  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    border = "rounded",
  })
end

function M.open(buf, float)
  if float then
    open_float(buf)
  else
    open_split(buf)
  end

  configure(vim.api.nvim_get_current_win())
end

return M
