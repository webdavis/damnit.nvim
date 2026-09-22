-- The statusline count, the due reminders, and the one poller behind both.
--
-- Every case drives `poll.apply` directly, so no case waits on a timer: what is
-- under test is the reading of an answer, not libuv's clock.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local poll = require("damnit.poll")
local queue = require("damnit.queue")

local TESTS_DIR = arg[0]:match("(.*)/") or "."

--- Dates read off the machine's own clock, because `poll.counts` reads the same
--- clock and a date written into a case here would age out of the state it was
--- chosen for.
local TODAY = os.date("%Y-%m-%d")
local YESTERDAY = os.date("%Y-%m-%d", os.time() - 86400)

---@param oid string
---@param value string?
---@return table
local function object(oid, value)
  return { oid = oid, subject = "x", path = "inbox/", task = { done = false, due = value } }
end

--- The `ls` line the fake recorded, if it recorded one.
---@param fake damnit.FakeDam
---@return string?
local function ls_line(fake)
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

    local line = ls_line(fake)
    queue.reset()
    poll.stop()
    fake_dam.remove(fake)

    -- `!done` is what keeps a task you just finished out of the count, because
    -- `due:today` matches a completed task as readily as an open one.
    assert(line == "ls !done & (due:today | overdue) --no-pull --json", tostring(line))
  end,

  ["counts what is due and what is overdue"] = function()
    poll.apply({ object("aaaa1111", TODAY), object("bbbb2222", YESTERDAY) }, nil)

    local shown = poll.status()
    poll.stop()

    assert(shown == "1 due, 1 overdue", shown)
  end,

  ["says dam ! rather than leaving a stale count standing"] = function()
    poll.apply({ object("aaaa1111", TODAY) }, nil)
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

    -- A component evaluated on every redraw draws nothing before the first
    -- answer, and asking for it is what starts the poller.
    assert(shown == "", shown)
    assert(running == true)
  end,

  ["setup starts the poller when reminders are on"] = function()
    poll.stop()

    require("damnit").setup({ reminders = true })
    local running = poll.running()

    poll.stop()
    require("damnit").setup({ reminders = false })

    -- A reminder nobody asked for costs a timer; one that was asked for has to
    -- arrive without a statusline component to start it.
    assert(running == true)
    assert(poll.running() == false)
  end,

  ["shows the count rather than its own fetch while the poller is reading"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
    queue.reset()
    poll.apply({ object("aaaa1111", TODAY) }, nil)

    poll.refresh()
    local shown = poll.status()

    fake_dam.settle(function()
      return queue.running() == nil
    end)
    queue.reset()
    poll.stop()
    fake_dam.remove(fake)

    -- The component whose whole job is the count would otherwise replace the
    -- count with its own fetch label, once every refresh_interval.
    assert(shown == "1 due", shown)
  end,

  ["shows the running operation instead of the count"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
    queue.reset()
    poll.apply({ object("aaaa1111", TODAY) }, nil)

    queue.submit({ args = { "push", "--json" }, label = "push todoist", verb = "push", network = true })

    local shown = poll.status()

    fake_dam.settle(function()
      return queue.running() == nil
    end)
    queue.reset()
    poll.stop()
    fake_dam.remove(fake)

    -- A push in flight is worth the slot more than a count that has not moved,
    -- and it is how a push started from a window that was then closed stays
    -- visible.
    assert(shown:match("^dam: push todoist %d+%.%ds$"), shown)
  end,

  ["leaves the lane alone while another call holds it"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
    queue.reset()

    queue.submit({ args = { "push", "--json" }, label = "push todoist", verb = "push", network = true })
    poll.refresh()

    fake_dam.settle(function()
      return queue.running() == nil
    end)

    local line = ls_line(fake)
    queue.reset()
    poll.stop()
    fake_dam.remove(fake)

    -- A poll queued behind a push answers about a store that push is still
    -- changing, and it arrives minutes after the count it reports went stale.
    assert(line == nil, tostring(line))
  end,

  ["says nothing about what was already overdue when the first fetch lands"] = function()
    require("damnit").options.reminders = true
    poll.stop()

    local said = {}
    local real = vim.notify
    vim.notify = function(text)
      table.insert(said, text)
    end

    local past = object("cccc3333", "2000-01-01T09:00:00")
    past.subject = "stand up"
    local later = object("dddd4444", "2000-01-01T10:00:00")
    later.subject = "sit down"

    poll.apply({ past }, nil)
    local after_first = #said

    poll.apply({ past, later }, nil)

    vim.notify = real
    require("damnit").options.reminders = false
    poll.stop()

    -- Opening the editor in the evening does not replay the morning.
    assert(after_first == 0, vim.inspect(said))
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

    local past = object("cccc3333", "2000-01-01T09:00:00")

    poll.apply({ past }, nil)
    poll.apply({ past, object("dddd4444", "2000-01-01T10:00:00") }, nil)

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

    local at_nine = object("cccc3333", "2000-01-01T09:00:00")
    at_nine.subject = "stand up"
    local at_eleven = object("cccc3333", "2000-01-01T11:00:00")
    at_eleven.subject = "stand up"

    poll.apply({ at_nine }, nil)
    local after_seed = #said

    poll.apply({ at_eleven }, nil)
    local after_move = #said

    poll.apply({ at_eleven }, nil)

    vim.notify = real
    require("damnit").options.reminders = false
    poll.stop()

    -- Keyed by the instant and not by the object, which is what makes a
    -- recurring task's next occurrence and a task moved to a new time both
    -- worth announcing again.
    assert(after_seed == 0, vim.inspect(said))
    assert(after_move == 1, vim.inspect(said))
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

    poll.apply({ object("aaaa1111", "2000-01-01") }, nil)
    poll.apply({ object("aaaa1111", "2000-01-01"), object("bbbb2222", "2000-01-02") }, nil)

    vim.notify = real
    require("damnit").options.reminders = false
    poll.stop()

    assert(#said == 0, vim.inspect(said))
  end,

  ["forgets its count when the poller stops, rather than freezing it"] = function()
    poll.apply({ object("aaaa1111", TODAY) }, nil)
    assert(poll.counts().due == 1)

    poll.stop()

    -- `status()` restarts the poller, so the reading is taken before it does.
    assert(poll.running() == false)
    assert(poll.counts().due == 0)
    assert(poll.counts().overdue == 0)
  end,
}
