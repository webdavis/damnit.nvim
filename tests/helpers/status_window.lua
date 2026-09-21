-- The status window, opened against a fake dam, for the length of one case.
--
-- Every spec that presses a key in the window drives the same setup: a fake dam
-- at the front of PATH, a captured `vim.notify`, one open window, and a full
-- teardown whether the case passed or not. It lives here so the specs that use
-- it cannot drift apart.

local M = {}

local TESTS_DIR = arg[0]:match("(.*)/") or "."

-- `:Dam` is declared by the plugin file rather than by `setup`, so a spec that
-- runs the command loads it the way Neovim would.
dofile(TESTS_DIR .. "/../plugin/damnit.lua")

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local queue = require("damnit.queue")
local window = require("damnit.window")

--- The fixture directory a case gets when it names none.
M.FIXTURES = TESTS_DIR .. "/fixtures/full"

--- Open the status window against a fake dam and hand it to `run`.
---@param run fun(fake: damnit.FakeDam, notifications: string[])
---@param fixtures string?
function M.with(run, fixtures)
  local fake = fake_dam.install({ fixtures = fixtures or M.FIXTURES })
  queue.reset()

  -- The remote list is read once per store and cached, so a case that asserts
  -- on it starts from a store this session has not read yet.
  window.forget_remotes()

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local buf = window.open()
  fake_dam.settle(function()
    return queue.running() == nil and vim.api.nvim_buf_line_count(buf) > 1
  end)

  local ok, err = pcall(run, fake, notifications)

  vim.notify = real
  vim.cmd("silent! %bwipeout!")
  queue.reset()
  fake_dam.remove(fake)

  assert(ok, err)
end

--- Run `run` with `vim.ui.input` answering `answer` rather than prompting.
---@param answer string?
---@param run fun()
function M.answer_input(answer, run)
  local real = vim.ui.input
  vim.ui.input = function(_, on_answer)
    on_answer(answer)
  end

  local ok, err = pcall(run)
  vim.ui.input = real

  assert(ok, err)
end

return M
