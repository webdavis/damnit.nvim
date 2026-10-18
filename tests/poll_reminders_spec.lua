local poll = require("damnit.poll")
local recording = require("helpers.said")

local function open_task_due(oid, due)
  return { oid = oid, subject = "x", path = "inbox/", task = { done = false, due = due } }
end

local function an_app_whose_reminders_are(on)
  local say, lines = recording.recorder()

  return { options = { reminders = on }, say = say }, lines
end

return {
  ["says nothing about what was already overdue when the first fetch lands"] = function()
    poll.stop()
    local reminding, said = an_app_whose_reminders_are(true)

    local past = open_task_due("cccc3333", "2000-01-01T09:00:00")
    past.subject = "stand up"
    local later = open_task_due("dddd4444", "2000-01-01T10:00:00")
    later.subject = "sit down"

    poll.apply(reminding, { past }, nil)
    local after_first = #said

    poll.apply(reminding, { past, later }, nil)

    poll.stop()

    assert(after_first == 0, "opening the editor in the evening does not replay the morning: " .. vim.inspect(said))
    assert(#said == 1, vim.inspect(said))
    assert(said[1]:find("sit down", 1, true), said[1])
  end,

  ["says nothing at all when reminders are off"] = function()
    poll.stop()
    local reminding, said = an_app_whose_reminders_are(false)

    local past = open_task_due("cccc3333", "2000-01-01T09:00:00")

    poll.apply(reminding, { past }, nil)
    poll.apply(reminding, { past, open_task_due("dddd4444", "2000-01-01T10:00:00") }, nil)

    poll.stop()

    assert(#said == 0, vim.inspect(said))
  end,

  ["announces a task again when its time moves, because the key carries the stamp"] = function()
    poll.stop()
    local reminding, said = an_app_whose_reminders_are(true)

    local at_nine = open_task_due("cccc3333", "2000-01-01T09:00:00")
    at_nine.subject = "stand up"
    local at_eleven = open_task_due("cccc3333", "2000-01-01T11:00:00")
    at_eleven.subject = "stand up"

    poll.apply(reminding, { at_nine }, nil)
    local after_seed = #said

    poll.apply(reminding, { at_eleven }, nil)
    local after_move = #said

    poll.apply(reminding, { at_eleven }, nil)

    poll.stop()

    assert(after_seed == 0, vim.inspect(said))
    assert(
      after_move == 1,
      "keyed by the instant, so a moved task or a recurring one's next time is announced again: " .. vim.inspect(said)
    )
    assert(#said == 1, "the same instant is announced once")
  end,

  ["announces a whole-day task never, because it has no moment to come due at"] = function()
    poll.stop()
    local reminding, said = an_app_whose_reminders_are(true)

    poll.apply(reminding, { open_task_due("aaaa1111", "2000-01-01") }, nil)
    poll.apply(reminding, { open_task_due("aaaa1111", "2000-01-01"), open_task_due("bbbb2222", "2000-01-02") }, nil)

    poll.stop()

    assert(#said == 0, vim.inspect(said))
  end,
}
