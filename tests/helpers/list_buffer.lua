local M = {}

local TESTS_DIR = arg[0]:match("(.*)/") or "."

local PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP = TESTS_DIR .. "/../plugin/damnit.lua"
dofile(PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP)

local fake_process = dofile(TESTS_DIR .. "/helpers/fake_process.lua")
local damnit = require("damnit")
local function queue()
  return require("damnit").app().queue
end
local views = require("damnit.views")

M.FIXTURES = TESTS_DIR .. "/fixtures/full"

local function forget_the_refused_view_names()
  views.reset()
end

function M.with(run, opts)
  opts = opts or {}

  local fake = fake_process.install({
    fixtures = opts.fixtures or M.FIXTURES,
    exit = opts.exit,
    stderr = opts.stderr,
  })

  forget_the_refused_view_names()
  damnit.options.views = opts.views or {}

  local notifications = fake.said

  local buf = opts.open and opts.open() or damnit.open(opts.name)
  fake_process.settle(function()
    return queue().running() == nil
  end)

  local ok, err = pcall(run, buf, fake, notifications)

  fake_process.drain()

  damnit.options.views = {}
  vim.cmd("silent! %bwipeout!")
  views.reset()
  fake_process.remove(fake)

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
