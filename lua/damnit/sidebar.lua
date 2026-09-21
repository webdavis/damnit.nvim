-- One dam view as a fixed-width sidebar.
--
-- The window is the state. A window-local flag marks the sidebar, so the
-- sidebar is whatever window in this tabpage carries that flag, and `:q` takes
-- the flag with the window. There is no separate record of being open, so the
-- plugin and Neovim cannot disagree about it.
--
-- The width is held the way nvim-tree and neo-tree hold theirs: `winfixwidth`
-- on the window, which survives a new split, a closed window, `wincmd =` and a
-- resized terminal. `winfixbuf` keeps another buffer out of the sidebar, so a
-- command that opens a file lands somewhere else. The one case `winfixwidth`
-- cannot cover is the sidebar being the only window in its tabpage, where
-- Neovim has nowhere else to put the columns; the autocommand below puts the
-- configured width back as soon as there is a second window to take the rest.

local M = {}

local message = require("damnit.message")

local FLAG = "damnit_sidebar"

---@return damnit.SidebarOptions
local function options()
  return require("damnit").options.sidebar
end

--- The sidebar window in this tabpage, if there is one. A sidebar in another
--- tabpage is another tabpage's window and is left alone.
---@return integer? win
function M.window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.w[win][FLAG] then
      return win
    end
  end
end

--- Hold the window at the configured width and keep other buffers out of it.
---@param win integer
---@param width integer
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

--- Open the sidebar, or focus it when it is already open here.
---
--- The view is resolved before the split is made, so a view name the plugin
--- was never given leaves the layout alone instead of parking an empty window.
---@return integer? win
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

  local spec = require("damnit.views").resolve(opts.view)
  if not spec then
    return
  end

  -- The far-side split spans the tabpage's height, which is what makes it a
  -- sidebar rather than a split of whichever window happened to be current.
  vim.cmd(opts.side == "right" and "botright vsplit" or "topleft vsplit")

  local win = vim.api.nvim_get_current_win()
  vim.w[win][FLAG] = true

  require("damnit.list").open(spec)
  hold(win, opts.width)

  return win
end

--- Move out of a window that refuses a new buffer, so a task or a file opened
--- from the sidebar lands in the work beside it rather than replacing the list.
function M.leave_fixed_window()
  if not vim.wo.winfixbuf then
    return
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not vim.wo[win].winfixbuf then
      return vim.api.nvim_set_current_win(win)
    end
  end

  -- Nowhere to put it. The far-side split takes its columns from the tabpage
  -- rather than out of the fixed window.
  vim.cmd("botright vsplit")
end

--- Close the sidebar, if this tabpage has one.
---@return boolean closed
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

--- Open the sidebar, or close the one this tabpage already has.
---
--- Answers with the window either way, so one type covers both: nil once the
--- sidebar is gone, and the window still there when the close was refused for
--- being the only one in the tabpage.
---@return integer? win the sidebar this tabpage has after the call
function M.toggle()
  if M.window() then
    M.close()

    return M.window()
  end

  return M.open()
end

-- `WinNew` is what catches a split made while the sidebar stood alone, and
-- `WinResized` catches a terminal that changed size in the same state.
vim.api.nvim_create_autocmd({ "WinNew", "WinResized" }, {
  group = vim.api.nvim_create_augroup("damnit-sidebar", { clear = true }),
  desc = "dam: hold the sidebar at its configured width",
  callback = function()
    local win = M.window()
    if not win or #vim.api.nvim_tabpage_list_wins(0) == 1 then
      return
    end

    local width = options().width
    if type(width) == "number" and width >= 1 and vim.api.nvim_win_get_width(win) ~= width then
      vim.api.nvim_win_set_width(win, width)
    end
  end,
})

return M
