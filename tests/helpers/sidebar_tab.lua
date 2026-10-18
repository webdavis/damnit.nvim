local M = {}

local fake_process = require("helpers.fake_process")
local harness = require("helpers.harness")

M.CONFIGURED_WIDTH = 34

local function a_tabpage_wide_enough_for_a_sidebar_and_a_split()
  vim.o.columns = 160
  vim.cmd("tabnew")
end

function M.opts(opts)
  return {
    fixtures = harness.fixtures("full"),
    options = {
      views = opts.views or { today = "due:today | overdue" },
      sidebar = {
        side = opts.side or "left",
        width = opts.width or M.CONFIGURED_WIDTH,
        view = opts.view or "today",
      },
    },
    open = a_tabpage_wide_enough_for_a_sidebar_and_a_split,
  }
end

function M.wait_until_drawn_from_dams_answer(win)
  fake_process.settle(function()
    return vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win)) > 3
  end)
end

function M.windows_in_this_tabpage()
  return #vim.api.nvim_tabpage_list_wins(0)
end

function M.cursor_to(win, needle)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)) do
    if line:find(needle, 1, true) then
      vim.api.nvim_win_set_cursor(win, { index, 0 })

      return
    end
  end

  error("no line holds " .. needle)
end

return M
