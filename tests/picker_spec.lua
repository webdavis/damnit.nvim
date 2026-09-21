-- Searching the objects of a view, by the line each one becomes and by the call
-- the search makes.
--
-- The front end is stubbed rather than driven: `vim.ui.select` in a headless
-- run has no terminal to read, and what these cases are about is which view was
-- asked for and what the entries carry.

local TESTS_DIR = arg[0]:match("(.*)/") or "."

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local list_buffer = dofile(TESTS_DIR .. "/helpers/list_buffer.lua")
local picker = require("damnit.picker")

local OBJECT = {
  oid = "78b8950b02735107aa608659dcf19f6f50adfeb1",
  subject = "buy oat milk",
  path = "inbox/",
  labels = { "errand", "home" },
  task = { priority = 1, due = "2026-09-25" },
}

--- Run `body` with `vim.ui.select` recording what it was offered rather than
--- reading a terminal, and hand it the record.
---
--- The record is what a case waits on: the argv log grows when the call is
--- spawned, and the entries only exist once its answer has been read.
---@param body fun(opened: string[][])
local function without_a_front_end(body)
  local real = vim.ui.select
  local opened = {}
  vim.ui.select = function(entries)
    table.insert(opened, entries)
  end

  local ok, err = pcall(body, opened)

  vim.ui.select = real
  assert(ok, err)
end

return {
  ["puts every field worth typing at on the line"] = function()
    local line = picker.line(OBJECT)

    for _, wanted in ipairs({ "buy oat milk", "2026-09-25", "p1", "errand", "home", "inbox/" }) do
      assert(line:find(wanted, 1, true), ("%q is missing from %q"):format(wanted, line))
    end
  end,

  ["carries the oid beside the line rather than in it"] = function()
    local entries = picker.entries({ OBJECT })

    assert(entries[1].oid == OBJECT.oid, entries[1].oid)
    assert(not entries[1].text:find(OBJECT.oid, 1, true), "forty characters of noise stay out of the line")
  end,

  ["follows the screen when it is given no name"] = function()
    list_buffer.with(function(_, fake)
      without_a_front_end(function(opened)
        local before = #fake_dam.argv_log(fake)
        picker.pick(nil)
        fake_dam.settle(function()
          return #opened == 1
        end)

        assert(
          fake_dam.argv_log(fake)[before + 1] == "ls due:today | overdue --json",
          vim.inspect(fake_dam.argv_log(fake))
        )

        vim.cmd("silent! %bwipeout!")
        local alone = #fake_dam.argv_log(fake)
        picker.pick(nil)
        fake_dam.settle(function()
          return #opened == 2
        end)

        assert(fake_dam.argv_log(fake)[alone + 1] == "ls --json", vim.inspect(fake_dam.argv_log(fake)))
      end)
    end, { views = { today = "due:today | overdue" }, name = "today" })
  end,
}
