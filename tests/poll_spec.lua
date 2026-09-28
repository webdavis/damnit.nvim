local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local poll = require("damnit.poll")
local queue = require("damnit.queue")

local TESTS_DIR = arg[0]:match("(.*)/") or "."

local TODAY_ON_THE_CLOCK_POLL_COUNTS_READS = os.date("%Y-%m-%d")
local YESTERDAY_ON_THE_CLOCK_POLL_COUNTS_READS = os.date("%Y-%m-%d", os.time() - 86400)

local function open_task_due(oid, due)
  return { oid = oid, subject = "x", path = "inbox/", task = { done = false, due = due } }
end

local function recorded_ls_line_or_nil(fake)
  for _, line in ipairs(fake_dam.argv_log(fake)) do
    if line:find("^ls ") then
      return line
    end
  end

  return nil
end

return {
  ["asks dam for the open objects due today or earlier, without a pull"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
    queue.reset()

    poll.refresh()
    fake_dam.settle(function()
      return queue.running() == nil
    end)

    local line = recorded_ls_line_or_nil(fake)
    queue.reset()
    poll.stop()
    fake_dam.remove(fake)

    assert(
      line == "ls !done & (due:today | overdue) --no-pull --json",
      "!done keeps a finished task out of the count, since due:today matches a completed one too: " .. tostring(line)
    )
  end,

  ["counts what is due and what is overdue"] = function()
    poll.apply({
      open_task_due("aaaa1111", TODAY_ON_THE_CLOCK_POLL_COUNTS_READS),
      open_task_due("bbbb2222", YESTERDAY_ON_THE_CLOCK_POLL_COUNTS_READS),
    }, nil)

    local shown = poll.status()
    poll.stop()

    assert(shown == "1 due, 1 overdue", shown)
  end,

  ["says dam ! rather than leaving a stale count standing"] = function()
    poll.apply({ open_task_due("aaaa1111", TODAY_ON_THE_CLOCK_POLL_COUNTS_READS) }, nil)
    poll.apply(nil, { kind = "error", code = 1, message = "storage: the store is locked" })

    local shown = poll.status()
    poll.stop()

    assert(shown == "dam !", shown)
  end,

  ["draws nothing at all when nothing is due"] = function()
    poll.apply({}, nil)

    local shown = poll.status()
    poll.stop()

    assert(shown == "", shown)
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

  ["shows the count rather than its own fetch while the poller is reading"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
    queue.reset()
    poll.apply({ open_task_due("aaaa1111", TODAY_ON_THE_CLOCK_POLL_COUNTS_READS) }, nil)

    poll.refresh()
    local shown = poll.status()

    fake_dam.settle(function()
      return queue.running() == nil
    end)
    queue.reset()
    poll.stop()
    fake_dam.remove(fake)

    assert(shown == "1 due", "the component whose job is the count shows no fetch label of its own: " .. shown)
  end,

  ["shows the running operation instead of the count"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
    queue.reset()
    poll.apply({ open_task_due("aaaa1111", TODAY_ON_THE_CLOCK_POLL_COUNTS_READS) }, nil)

    queue.submit({ args = { "push", "--json" }, label = "push todoist", verb = "push", network = true })

    local shown = poll.status()

    fake_dam.settle(function()
      return queue.running() == nil
    end)
    queue.reset()
    poll.stop()
    fake_dam.remove(fake)

    assert(
      shown:match("^dam: push todoist %d+%.%ds$"),
      "a push in flight outranks a count that has not moved, and stays visible once its window closes: " .. shown
    )
  end,

  ["leaves the lane alone while another call holds it"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
    queue.reset()

    queue.submit({ args = { "push", "--json" }, label = "push todoist", verb = "push", network = true })
    poll.refresh()

    fake_dam.settle(function()
      return queue.running() == nil
    end)

    local line = recorded_ls_line_or_nil(fake)
    queue.reset()
    poll.stop()
    fake_dam.remove(fake)

    assert(
      line == nil,
      "a poll queued behind a push would answer about a store the push is still changing: " .. tostring(line)
    )
  end,

  ["says nothing about what was already overdue when the first fetch lands"] = function()
    require("damnit").options.reminders = true
    poll.stop()

    local said = {}
    local real = vim.notify
    vim.notify = function(text)
      table.insert(said, text)
    end

    local past = open_task_due("cccc3333", "2000-01-01T09:00:00")
    past.subject = "stand up"
    local later = open_task_due("dddd4444", "2000-01-01T10:00:00")
    later.subject = "sit down"

    poll.apply({ past }, nil)
    local after_first = #said

    poll.apply({ past, later }, nil)

    vim.notify = real
    require("damnit").options.reminders = false
    poll.stop()

    assert(after_first == 0, "opening the editor in the evening does not replay the morning: " .. vim.inspect(said))
    assert(#said == 1, vim.inspect(said))
    assert(said[1]:find("sit down", 1, true), said[1])
  end,

  ["says nothing at all when reminders are off"] = function()
    poll.stop()

    local said = {}
    local real = vim.notify
    vim.notify = function(text)
      table.insert(said, text)
    end

    local past = open_task_due("cccc3333", "2000-01-01T09:00:00")

    poll.apply({ past }, nil)
    poll.apply({ past, open_task_due("dddd4444", "2000-01-01T10:00:00") }, nil)

    vim.notify = real
    poll.stop()

    assert(#said == 0, vim.inspect(said))
  end,

  ["announces a task again when its time moves, because the key carries the stamp"] = function()
    require("damnit").options.reminders = true
    poll.stop()

    local said = {}
    local real = vim.notify
    vim.notify = function(text)
      table.insert(said, text)
    end

    local at_nine = open_task_due("cccc3333", "2000-01-01T09:00:00")
    at_nine.subject = "stand up"
    local at_eleven = open_task_due("cccc3333", "2000-01-01T11:00:00")
    at_eleven.subject = "stand up"

    poll.apply({ at_nine }, nil)
    local after_seed = #said

    poll.apply({ at_eleven }, nil)
    local after_move = #said

    poll.apply({ at_eleven }, nil)

    vim.notify = real
    require("damnit").options.reminders = false
    poll.stop()

    assert(after_seed == 0, vim.inspect(said))
    assert(
      after_move == 1,
      "keyed by the instant, so a moved task or a recurring one's next time is announced again: " .. vim.inspect(said)
    )
    assert(#said == 1, "the same instant is announced once")
  end,

  ["announces a whole-day task never, because it has no moment to come due at"] = function()
    require("damnit").options.reminders = true
    poll.stop()

    local said = {}
    local real = vim.notify
    vim.notify = function(text)
      table.insert(said, text)
    end

    poll.apply({ open_task_due("aaaa1111", "2000-01-01") }, nil)
    poll.apply({ open_task_due("aaaa1111", "2000-01-01"), open_task_due("bbbb2222", "2000-01-02") }, nil)

    vim.notify = real
    require("damnit").options.reminders = false
    poll.stop()

    assert(#said == 0, vim.inspect(said))
  end,

  ["forgets its count when the poller stops, rather than freezing it"] = function()
    poll.apply({ open_task_due("aaaa1111", TODAY_ON_THE_CLOCK_POLL_COUNTS_READS) }, nil)
    assert(poll.counts().due == 1)

    poll.stop()

    assert(poll.running() == false, "read through counts(), because status() would restart the poller")
    assert(poll.counts().due == 0)
    assert(poll.counts().overdue == 0)
  end,
}
