local M = {}

local message = require("damnit.message")

local SIDEBAR_WINDOW_FLAG = "damnit_sidebar"

local function options()
  return require("damnit").options.sidebar
end

function M.window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.w[win][SIDEBAR_WINDOW_FLAG] then
      return win
    end
  end
end

local function hold(win, width)
  vim.api.nvim_win_set_width(win, width)

  vim.wo[win].winfixwidth = true
  vim.wo[win].winfixheight = true
  vim.wo[win].winfixbuf = true
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
end

local function split_full_height_at(side)
  vim.cmd(side == "right" and "botright vsplit" or "topleft vsplit")
end

local function open_beside(spec, opts)
  split_full_height_at(opts.side)

  local win = vim.api.nvim_get_current_win()
  vim.w[win][SIDEBAR_WINDOW_FLAG] = true

  require("damnit.list").open(spec)
  hold(win, opts.width)

  return win
end

function M.open()
  local existing = M.window()
  if existing then
    vim.api.nvim_set_current_win(existing)
    return existing
  end

  local opts = options()

  if opts.side ~= "left" and opts.side ~= "right" then
    return message.fail(('sidebar.side is %q, and it is either "left" or "right"'):format(tostring(opts.side)))
  end

  if type(opts.width) ~= "number" or opts.width < 1 then
    return message.fail(("sidebar.width is %s, and it is a count of columns"):format(vim.inspect(opts.width)))
  end

  return require("damnit.views").resolve_then(opts.view, function(spec)
    return open_beside(spec, opts)
  end)
end

function M.leave_fixed_window()
  if not vim.wo.winfixbuf then
    return
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not vim.wo[win].winfixbuf then
      return vim.api.nvim_set_current_win(win)
    end
  end

  split_full_height_at("right")
end

function M.close()
  local win = M.window()
  if not win then
    return false
  end

  if #vim.api.nvim_tabpage_list_wins(0) == 1 then
    message.warn("the sidebar is the only window here, so closing it would leave nothing")

    return false
  end

  vim.api.nvim_win_close(win, false)

  return true
end

function M.toggle()
  if M.window() then
    M.close()

    return M.window()
  end

  return M.open()
end

local function restore_the_width_once_another_window_takes_the_rest()
  local win = M.window()
  if not win or #vim.api.nvim_tabpage_list_wins(0) == 1 then
    return
  end

  local width = options().width
  if type(width) == "number" and width >= 1 and vim.api.nvim_win_get_width(win) ~= width then
    vim.api.nvim_win_set_width(win, width)
  end
end

vim.api.nvim_create_autocmd({ "WinNew", "WinResized" }, {
  group = vim.api.nvim_create_augroup("damnit-sidebar", { clear = true }),
  desc = "dam: hold the sidebar at its configured width",
  callback = restore_the_width_once_another_window_takes_the_rest,
})

return M
