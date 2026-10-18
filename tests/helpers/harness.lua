local M = {}

local damnit = require("damnit")
local fake_process = require("helpers.fake_process")
local paths = require("helpers.paths")
local screen = require("helpers.screen")
local window = require("damnit.window")

function M.fixtures(name)
  return ("%s/fixtures/%s"):format(paths.TESTS, name)
end

local function forget_what_the_last_case_left_in_module_state()
  local app = damnit.app()
  window.forget_remotes(app)

  local diffs = window.open_diffs(app)
  for oid in pairs(diffs) do
    diffs[oid] = nil
  end
end

local function swap_the_prompts(opts)
  local input, select = vim.ui.input, vim.ui.select
  vim.ui.input = opts.input or input
  vim.ui.select = opts.select or select

  return function()
    vim.ui.input, vim.ui.select = input, select
  end
end

local function close_every_window_and_buffer_the_case_opened(tab)
  vim.api.nvim_set_current_tabpage(tab)
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  vim.cmd("silent! %bwipeout!")
  vim.wo.wrap = true
end

local function deliver_late_answers_only_once_their_windows_are_closed()
  fake_process.drain()
end

function M.with_dam(opts, body)
  local options, columns, lines = damnit.options, vim.o.columns, vim.o.lines
  local tab = vim.api.nvim_get_current_tabpage()
  damnit.options = vim.tbl_deep_extend("force", options, opts.options or {})

  local fake = fake_process.install(opts)
  forget_what_the_last_case_left_in_module_state()
  local restore_the_prompts = swap_the_prompts(opts)

  local dam = { fake = fake, sent = fake.argv, said = fake.said, levels = fake.levels, screen = screen }
  local ok, err = pcall(function()
    dam.buf = opts.open and opts.open(damnit.app())
    fake_process.drain()
    body(dam)
  end)

  restore_the_prompts()
  close_every_window_and_buffer_the_case_opened(tab)
  deliver_late_answers_only_once_their_windows_are_closed()
  vim.o.columns, vim.o.lines = columns, lines
  damnit.options = options
  fake_process.remove(fake)

  assert(ok, err)

  return dam
end

return M
