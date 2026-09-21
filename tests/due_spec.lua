-- Where a task stands against the clock.
--
-- Every case hands in its own clock, so no answer here depends on the day the
-- suite runs, the hour it runs at, or the timezone of the machine running it.

local due = require("damnit.due")

--- A clock five hours behind UTC, at two in the afternoon on a fixed day.
---@param stamp string?
---@param utc_offset integer?
---@return { stamp: string, utc_offset: integer }
local function clock(stamp, utc_offset)
  return { stamp = stamp or "2026-09-17T14:00:00", utc_offset = utc_offset or -5 * 3600 }
end

--- One object's `task` sub-table, which is where dam puts `due`.
---@param value any
---@return table
local function task(value)
  return { done = false, priority = 4, due = value }
end

return {
  ["a task with no due field is neither due nor overdue"] = function()
    assert(due.classify({ done = false, priority = 4 }, clock()) == "none")
  end,

  ["a null due decodes to vim.NIL, which is truthy, and is still not due"] = function()
    assert(due.classify(task(vim.NIL), clock()) == "none")
  end,

  ["a full-day task due today is due, not overdue, in the afternoon"] = function()
    assert(due.classify(task("2026-09-17"), clock("2026-09-17T14:00:00")) == "due")
  end,

  ["a full-day task due today is still due one minute before midnight"] = function()
    assert(due.classify(task("2026-09-17"), clock("2026-09-17T23:59:00")) == "due")
  end,

  ["a full-day task due yesterday is overdue"] = function()
    assert(due.classify(task("2026-09-16"), clock()) == "overdue")
  end,

  ["a full-day task due tomorrow is neither"] = function()
    assert(due.classify(task("2026-09-18"), clock()) == "later")
  end,

  ["a task due today at nine is overdue at two in the afternoon"] = function()
    local where, timed = due.classify(task("2026-09-17T09:00:00"), clock("2026-09-17T14:00:00"))
    assert(where == "overdue", where)
    assert(timed)
  end,

  ["the same task is due, not overdue, at eight in the morning"] = function()
    assert(due.classify(task("2026-09-17T09:00:00"), clock("2026-09-17T08:00:00")) == "due")
  end,

  ["a task is overdue from its own minute on"] = function()
    assert(due.classify(task("2026-09-17T09:00:00"), clock("2026-09-17T09:00:00")) == "overdue")
    assert(due.classify(task("2026-09-17T09:00:00"), clock("2026-09-17T08:59:59")) == "due")
  end,

  ["a full-day task carries no time and a timed one does"] = function()
    local _, all_day = due.classify(task("2026-09-17"), clock())
    local _, timed = due.classify(task("2026-09-17T09:00:00"), clock())
    assert(all_day == false)
    assert(timed == true)
  end,

  ["a zoned due in the clock's own offset is read as written"] = function()
    -- The shape dam stores a timed due as: the instant, its offset, its zone.
    local where, timed, stamp = due.classify(task("2026-09-17T09:00:00-05:00[America/Chicago]"), clock())
    assert(stamp == "2026-09-17T09:00:00", stamp)
    assert(where == "overdue", where)
    assert(timed)
  end,

  ["a zoned due from another zone is shifted into local time"] = function()
    -- 18:00 in a zone two hours ahead of UTC is 11:00 five hours behind it.
    local where, _, stamp = due.classify(task("2026-09-17T18:00:00+02:00[Europe/Berlin]"), clock("2026-09-17T10:00:00"))
    assert(stamp == "2026-09-17T11:00:00", stamp)
    assert(where == "due", where)
  end,

  ["a fixed-zone due is stored in UTC and read in local time"] = function()
    -- 18:00 UTC is 13:00 on a clock five hours behind, so it has not come yet.
    local where, _, stamp = due.classify(task("2026-09-17T18:00:00.000000Z"), clock("2026-09-17T12:00:00"))
    assert(stamp == "2026-09-17T13:00:00", stamp)
    assert(where == "due", where)
  end,

  ["a fixed-zone due already past in local time is overdue"] = function()
    assert(due.classify(task("2026-09-17T18:00:00.000000Z"), clock("2026-09-17T14:00:00")) == "overdue")
  end,

  ["a UTC due late in the day belongs to the local day it lands on"] = function()
    -- 02:00 UTC on the 18th is 21:00 on the 17th five hours behind.
    local _, _, stamp = due.classify(task("2026-09-18T02:00:00Z"), clock("2026-09-17T14:00:00"))
    assert(stamp == "2026-09-17T21:00:00", stamp)
    assert(due.classify(task("2026-09-18T02:00:00Z"), clock("2026-09-17T14:00:00")) == "due")
  end,

  ["a due carrying no offset at all is read as written"] = function()
    local _, _, stamp = due.classify(task("2026-09-17T09:00:00"), clock("2026-09-17T14:00:00", 9 * 3600))
    assert(stamp == "2026-09-17T09:00:00", stamp)
  end,

  ["a due date in a shape nothing recognises is not counted"] = function()
    assert(due.classify(task("next tuesday"), clock()) == "none")
  end,

  ["the clock reads the machine as a stamp and an offset"] = function()
    local now = due.clock()
    assert(now.stamp:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d$"), now.stamp)
    assert(type(now.utc_offset) == "number")
  end,

  ["the clock's offset matches the machine's own %z, not the daylight-saving-blind version"] = function()
    local sign, hours, minutes = os.date("%z"):match("^([+-])(%d%d)(%d%d)$")
    local expected = (tonumber(sign .. hours) * 3600) + (tonumber(sign .. minutes) * 60)
    local now = due.clock()
    assert(now.utc_offset == expected, ("got %d, wanted %d"):format(now.utc_offset, expected))
  end,
}
