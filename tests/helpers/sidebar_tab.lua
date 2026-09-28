local M = {}

local TESTS_DIR = arg[0]:match("(.*)/") or "."

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local damnit = require("damnit")
local list = require("damnit.list")
local queue = require("damnit.queue")
local views = require("damnit.views")

M.CONFIGURED_WIDTH = 34

local function cancel_only_a_call_still_in_flight_since_cancelling_none_says_so_aloud()
  if queue.running() then
    queue.cancel()
  end
end

function M.in_its_own_tabpage(opts, body)
  local options = damnit.options
  local real_notify = vim.notify
  local columns = vim.o.columns

  damnit.options = vim.tbl_deep_extend("force", options, {
    views = opts.views or { today = "due:today | overdue" },
    sidebar = {
      side = opts.side or "left",
      width = opts.width or M.CONFIGURED_WIDTH,
      view = opts.view or "today",
    },
  })

  local fake = fake_dam.install({
    fixtures = TESTS_DIR .. "/fixtures/full",
    sleep = opts.slow_first_fetch and "5" or nil,
  })
  queue.reset()
  list.forget_folds()
  views.reset()

  local notifications = {}
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  vim.o.columns = 160
  vim.cmd("tabnew")
  local tab = vim.api.nvim_get_current_tabpage()

  local ok, result = pcall(body, fake)

  vim.cmd("tabclose")
  if vim.api.nvim_tabpage_is_valid(tab) then
    vim.api.nvim_set_current_tabpage(tab)
    vim.cmd("tabclose")
  end

  vim.o.columns = columns
  vim.notify = real_notify
  vim.cmd("silent! %bwipeout!")

  cancel_only_a_call_still_in_flight_since_cancelling_none_says_so_aloud()
  queue.reset()
  views.reset()
  fake_dam.remove(fake)
  damnit.options = options

  assert(ok, result)

  return result, notifications
end

function M.wait_until_drawn_from_dams_answer(win)
  fake_dam.settle(function()
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
