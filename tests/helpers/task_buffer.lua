local M = {}

local TESTS_DIR = arg[0]:match("(.*)/") or "."

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local queue = require("damnit.queue")
local task_buffer = require("damnit.task_buffer")

M.OID = "badb4903b653809e591c31118004e07de7c8183c"

function M.with_task(run, opts)
  local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full", fail = (opts or {}).fail })
  queue.reset()

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local open = (opts or {}).open or task_buffer.open
  local buf = open(M.OID) or vim.api.nvim_get_current_buf()
  fake_dam.settle(function()
    return vim.api.nvim_buf_line_count(buf) > 1
  end)

  local ok, err = pcall(run, buf, fake, notifications)

  vim.notify = real
  vim.cmd("silent! %bwipeout!")
  queue.reset()
  fake_dam.remove(fake)

  assert(ok, err)
end

function M.set_field(buf, key, value)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:match("^" .. key .. ":") then
      vim.api.nvim_buf_set_lines(buf, index - 1, index, false, { ("%s: %s"):format(key, value) })

      return
    end
  end

  error("no " .. key .. " line in the buffer")
end

function M.field_index(buf, key)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if vim.startswith(line, key .. ":") then
      return index
    end
  end
end

function M.field_line(buf, key)
  local index = M.field_index(buf, key)

  return index and vim.api.nvim_buf_get_lines(buf, index - 1, index, false)[1]
end

function M.diagnostics(buf)
  return vim.diagnostic.get(buf, { namespace = task_buffer.NAMESPACE })
end

function M.argv_the_write_sent_or_nil(fake)
  local before = #fake_dam.argv_log(fake)
  vim.cmd("write")

  if not fake_dam.wait_long_enough_to_catch_a_stray_call(fake, before) then
    return nil
  end

  return fake_dam.argv_log(fake)[before + 1]
end

function M.write_a_new_subject_and_path_then_settle(buf, fake)
  M.set_field(buf, "subject", "buy the oat milk")
  M.set_field(buf, "path", "home/inbox/")

  local before = #fake_dam.argv_log(fake)
  vim.cmd("write")
  fake_dam.settle(function()
    return #M.diagnostics(buf) > 0 or vim.bo[buf].modified == false
  end)
  fake_dam.wait_long_enough_to_catch_a_stray_call(fake, #fake_dam.argv_log(fake))

  return vim.list_slice(fake_dam.argv_log(fake), before + 1)
end

return M
