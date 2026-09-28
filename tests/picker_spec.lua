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

local function wait_until_the_answer_was_read_and_offered(offered, count)
  fake_dam.settle(function()
    return #offered == count
  end)
end

local function with_select_recording_what_it_offered(body)
  local real = vim.ui.select
  local offered = {}
  vim.ui.select = function(entries)
    table.insert(offered, entries)
  end

  local ok, err = pcall(body, offered)

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
      with_select_recording_what_it_offered(function(offered)
        local before = #fake_dam.argv_log(fake)
        picker.pick(nil)
        wait_until_the_answer_was_read_and_offered(offered, 1)

        assert(
          fake_dam.argv_log(fake)[before + 1] == "ls due:today | overdue --json",
          vim.inspect(fake_dam.argv_log(fake))
        )

        vim.cmd("silent! %bwipeout!")
        local alone = #fake_dam.argv_log(fake)
        picker.pick(nil)
        wait_until_the_answer_was_read_and_offered(offered, 2)

        assert(fake_dam.argv_log(fake)[alone + 1] == "ls --json", vim.inspect(fake_dam.argv_log(fake)))
      end)
    end, { views = { today = "due:today | overdue" }, name = "today" })
  end,

  ["says dam's own reason when the view it searches is refused, and offers nothing"] = function()
    list_buffer.with(function(_, fake, notifications)
      with_select_recording_what_it_offered(function(offered)
        local logged_before = #fake_dam.argv_log(fake)
        local said_before = #notifications

        picker.pick("today")
        fake_dam.settle(function()
          return #fake_dam.argv_log(fake) > logged_before and require("damnit.queue").running() == nil
        end)

        assert(#offered == 0, "a refused view offered " .. vim.inspect(offered))
        assert(notifications[said_before + 1] == "the store is locked", vim.inspect(notifications))
      end)
    end, {
      views = { today = "due:today | overdue" },
      name = "today",
      exit = 1,
      stderr = '{"error": {"kind": "store", "rule": null, "message": "the store is locked", "oids": []}}',
    })
  end,
}
