-- The list buffer, opened against a fake dam, for the length of one case.
--
-- Every spec that presses a key in the list drives the same setup: a fake dam
-- at the front of PATH, a captured `vim.notify`, one open list, and a full
-- teardown whether the case passed or not.

local M = {}

local TESTS_DIR = arg[0]:match("(.*)/") or "."

-- `:Dam` is declared by the plugin file rather than by `setup`, so a spec that
-- runs the command loads it the way Neovim would.
dofile(TESTS_DIR .. "/../plugin/damnit.lua")

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local damnit = require("damnit")
local list = require("damnit.list")
local queue = require("damnit.queue")
local views = require("damnit.views")

--- The fixture directory a case gets when it names none.
M.FIXTURES = TESTS_DIR .. "/fixtures/full"

--- Open a list against a fake dam and hand it to `run`.
---@param run fun(buf: integer, fake: damnit.FakeDam, notifications: string[])
---@param opts { views: table?, name: string?, fixtures: string?, exit: integer?, stderr: string? }?
function M.with(run, opts)
  opts = opts or {}

  local fake = fake_dam.install({
    fixtures = opts.fixtures or M.FIXTURES,
    exit = opts.exit,
    stderr = opts.stderr,
  })
  queue.reset()

  -- Both are the session's, not the buffer's, so a case starts from a list
  -- that has folded nothing and refused no view name.
  list.forget_folds()
  views.reset()
  damnit.options.views = opts.views or {}

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local buf = damnit.open(opts.name)
  fake_dam.settle(function()
    return queue.running() == nil
  end)

  local ok, err = pcall(run, buf, fake, notifications)

  vim.notify = real
  damnit.options.views = {}
  vim.cmd("silent! %bwipeout!")
  queue.reset()
  views.reset()
  fake_dam.remove(fake)

  assert(ok, err)
end

--- Put the cursor on the line holding `needle`.
---@param buf integer
---@param needle string
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
