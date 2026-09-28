local M = {}

local TESTS_DIR = arg[0]:match("(.*)/") or "."

local PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP = TESTS_DIR .. "/../plugin/damnit.lua"
dofile(PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP)

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local damnit = require("damnit")
local list = require("damnit.list")
local queue = require("damnit.queue")
local views = require("damnit.views")

M.FIXTURES = TESTS_DIR .. "/fixtures/full"

local function forget_the_session_folds_and_refused_view_names()
  list.forget_folds()
  views.reset()
end

function M.with(run, opts)
  opts = opts or {}

  local fake = fake_dam.install({
    fixtures = opts.fixtures or M.FIXTURES,
    exit = opts.exit,
    stderr = opts.stderr,
  })
  queue.reset()

  forget_the_session_folds_and_refused_view_names()
  damnit.options.views = opts.views or {}

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local buf = opts.open and opts.open() or damnit.open(opts.name)
  fake_dam.settle(function()
    return queue.running() == nil
  end)

  local ok, err = pcall(run, buf, fake, notifications)

  fake_dam.drain_the_lane_so_no_answer_lands_in_the_next_case()

  vim.notify = real
  damnit.options.views = {}
  vim.cmd("silent! %bwipeout!")
  queue.reset()
  views.reset()
  fake_dam.remove(fake)

  assert(ok, err)
end

function M.cursor_to(buf, needle)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:find(needle, 1, true) then
      vim.api.nvim_win_set_cursor(0, { index, 0 })

      return
    end
  end

  error("no line holds " .. needle)
end

return M
