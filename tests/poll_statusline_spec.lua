local with_dam = require("helpers.harness").with_dam
local harness = require("helpers.harness")
local app = require("damnit").app()
local fake_process = require("helpers.fake_process")
local poll = require("damnit.poll")
local clock = require("helpers.clock")
local function queue()
  return require("damnit").app().queue
end

local NOON_UTC_ON_THE_FIRST_OF_OCTOBER = 1790856000
local THE_FIRST_OF_OCTOBER = "2026-10-01"
local THE_LAST_OF_SEPTEMBER = "2026-09-30"

local function open_task_due(oid, due)
  return { oid = oid, subject = "x", path = "inbox/", task = { done = false, due = due } }
end

return {
  ["counts what is due and what is overdue"] = function()
    clock.at(NOON_UTC_ON_THE_FIRST_OF_OCTOBER, function()
      poll.apply(app, {
        open_task_due("aaaa1111", THE_FIRST_OF_OCTOBER),
        open_task_due("bbbb2222", THE_LAST_OF_SEPTEMBER),
      }, nil)

      local shown = poll.status(app)
      poll.stop()

      assert(shown == "1 due, 1 overdue", shown)
    end)
  end,

  ["says dam ! rather than leaving a stale count standing"] = function()
    clock.at(NOON_UTC_ON_THE_FIRST_OF_OCTOBER, function()
      poll.apply(app, { open_task_due("aaaa1111", THE_FIRST_OF_OCTOBER) }, nil)
      poll.apply(app, nil, { kind = "error", code = 1, message = "storage: the store is locked" })

      local shown = poll.status(app)
      poll.stop()

      assert(shown == "dam !", shown)
    end)
  end,

  ["draws nothing at all when nothing is due"] = function()
    poll.apply(app, {}, nil)

    local shown = poll.status(app)
    poll.stop()

    assert(shown == "", shown)
  end,

  ["shows the count rather than its own fetch while the poller is reading"] = function()
    clock.at(NOON_UTC_ON_THE_FIRST_OF_OCTOBER, function()
      with_dam({ fixtures = harness.fixtures("full") }, function()
        poll.apply(app, { open_task_due("aaaa1111", THE_FIRST_OF_OCTOBER) }, nil)

        poll.refresh(app)
        local shown = poll.status(app)

        fake_process.settle(function()
          return queue().running() == nil
        end)
        poll.stop()

        assert(shown == "1 due", "the component whose job is the count shows no fetch label of its own: " .. shown)
      end)
    end)
  end,

  ["shows the running operation instead of the count"] = function()
    clock.at(NOON_UTC_ON_THE_FIRST_OF_OCTOBER, function()
      with_dam({ fixtures = harness.fixtures("full") }, function()
        poll.apply(app, { open_task_due("aaaa1111", THE_FIRST_OF_OCTOBER) }, nil)

        queue().submit({ args = { "push", "--json" }, label = "push todoist", verb = "push", network = true })

        local shown = poll.status(app)

        fake_process.settle(function()
          return queue().running() == nil
        end)
        poll.stop()

        assert(
          shown:match("^dam: push todoist %d+%.%ds$"),
          "a push in flight outranks a count that has not moved, and stays visible once its window closes: " .. shown
        )
      end)
    end)
  end,
}
