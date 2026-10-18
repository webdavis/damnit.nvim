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

local function open_task_due(oid, due)
  return { oid = oid, subject = "x", path = "inbox/", task = { done = false, due = due } }
end

local function recorded_ls_line_or_nil(fake)
  for _, line in ipairs(fake_process.argv_log(fake)) do
    if line:find("^ls ") then
      return line
    end
  end

  return nil
end

return {
  ["asks dam for the open objects due today or earlier, without a pull"] = function()
    with_dam({ fixtures = harness.fixtures("full") }, function(dam)
      poll.refresh(app)
      fake_process.settle(function()
        return queue().running() == nil
      end)

      local line = recorded_ls_line_or_nil(dam.fake)
      poll.stop()

      assert(
        line == "ls !done & (due:today | overdue) --no-pull --json",
        "!done keeps a finished task out of the count, since due:today matches a completed one too: " .. tostring(line)
      )
    end)
  end,

  ["the statusline function the README names is the poller's own"] = function()
    poll.stop()

    local shown = require("damnit").status()
    local running = poll.running()
    poll.stop()

    assert(shown == "", "a component evaluated on every redraw draws nothing before the first answer: " .. shown)
    assert(running == true, "asking for the component is what starts the poller")
  end,

  ["setup starts the poller when reminders are on"] = function()
    poll.stop()

    require("damnit").setup({ reminders = true })
    local running = poll.running()

    poll.stop()
    require("damnit").setup({ reminders = false })

    assert(running == true, "a reminder asked for arrives without a statusline component to start the poller")
    assert(poll.running() == false, "a reminder nobody asked for costs no timer")
  end,

  ["leaves the lane alone while another call holds it"] = function()
    with_dam({ fixtures = harness.fixtures("full") }, function(dam)
      queue().submit({ args = { "push", "--json" }, label = "push todoist", verb = "push", network = true })
      poll.refresh(app)

      fake_process.settle(function()
        return queue().running() == nil
      end)

      local line = recorded_ls_line_or_nil(dam.fake)
      poll.stop()

      assert(
        line == nil,
        "a poll queued behind a push would answer about a store the push is still changing: " .. tostring(line)
      )
    end)
  end,

  ["forgets its count when the poller stops, rather than freezing it"] = function()
    clock.at(NOON_UTC_ON_THE_FIRST_OF_OCTOBER, function()
      poll.apply(app, { open_task_due("aaaa1111", THE_FIRST_OF_OCTOBER) }, nil)
      assert(poll.counts().due == 1)

      poll.stop()

      assert(poll.running() == false, "read through counts(), because status() would restart the poller")
      assert(poll.counts().due == 0)
      assert(poll.counts().overdue == 0)
    end)
  end,
}
