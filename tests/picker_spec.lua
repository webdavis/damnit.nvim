local with_dam = require("helpers.harness").with_dam
local app = require("damnit").app()

local fake_process = require("helpers.fake_process")
local list_buffer = require("helpers.list_buffer")
local picker = require("damnit.picker")

local OBJECT = {
  oid = "78b8950b02735107aa608659dcf19f6f50adfeb1",
  subject = "buy oat milk",
  path = "inbox/",
  labels = { "errand", "home" },
  task = { priority = 1, due = "2026-09-25" },
}

local function wait_until_the_answer_was_read_and_offered(offered, count)
  fake_process.settle(function()
    return #offered == count
  end)
end

local function a_select_recording_what_it_offered()
  local offered = {}

  return offered, function(entries)
    table.insert(offered, entries)
  end
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
    local offered, select = a_select_recording_what_it_offered()

    with_dam(
      list_buffer.opts({ views = { today = "due:today | overdue" }, name = "today", select = select }),
      function(dam)
        local before = #fake_process.argv_log(dam.fake)
        picker.pick(app, nil)
        wait_until_the_answer_was_read_and_offered(offered, 1)

        assert(
          fake_process.argv_log(dam.fake)[before + 1] == "ls due:today | overdue --json",
          vim.inspect(fake_process.argv_log(dam.fake))
        )

        vim.cmd("silent! %bwipeout!")
        local alone = #fake_process.argv_log(dam.fake)
        picker.pick(app, nil)
        wait_until_the_answer_was_read_and_offered(offered, 2)

        assert(
          fake_process.argv_log(dam.fake)[alone + 1] == "ls !done --json",
          vim.inspect(fake_process.argv_log(dam.fake))
        )
      end
    )
  end,

  ["says dam's own reason when the view it searches is refused, and offers nothing"] = function()
    local offered, select = a_select_recording_what_it_offered()

    with_dam(
      list_buffer.opts({
        views = { today = "due:today | overdue" },
        name = "today",
        exit = 1,
        stderr = '{"error": {"kind": "store", "rule": null, "message": "the store is locked", "oids": []}}',
        select = select,
      }),
      function(dam)
        local logged_before = #fake_process.argv_log(dam.fake)
        local said_before = #dam.said

        picker.pick(app, "today")
        fake_process.settle(function()
          return #fake_process.argv_log(dam.fake) > logged_before and require("damnit").app().queue.running() == nil
        end)

        assert(#offered == 0, "a refused view offered " .. vim.inspect(offered))
        assert(dam.said[said_before + 1] == "damnit.nvim: the store is locked", vim.inspect(dam.said))
      end
    )
  end,
}
