local M = {}

local TESTS_DIR = arg[0]:match("(.*)/") or "."

local PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP = TESTS_DIR .. "/../plugin/damnit.lua"
dofile(PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP)

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local queue = require("damnit.queue")
local window = require("damnit.window")

M.FIXTURES = TESTS_DIR .. "/fixtures/full"

local function forget_the_remote_list_cached_per_store()
  window.forget_remotes()
end

local function forget_the_diffs_remembered_for_the_session()
  local diffs = window.open_diffs()
  for oid in pairs(diffs) do
    diffs[oid] = nil
  end
end

function M.with(run, fixtures)
  local fake = fake_dam.install({ fixtures = fixtures or M.FIXTURES })
  queue.reset()

  forget_the_remote_list_cached_per_store()
  forget_the_diffs_remembered_for_the_session()

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

function M.answer_input(answer, run, on_prompt)
  local real = vim.ui.input
  vim.ui.input = function(opts, on_answer)
    if on_prompt then
      on_prompt(opts.prompt)
    end
    on_answer(answer)
  end

  local ok, err = pcall(run)
  vim.ui.input = real

  assert(ok, err)
end

return M
