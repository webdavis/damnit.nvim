-- When a task is due, read against a clock that is handed in.
--
-- Todoist's `due` object has three shapes and this is the one place that knows
-- them. Its fields are `date`, `timezone`, `string`, `lang` and `is_recurring`,
-- and the shapes are a full-day date (`date` is `YYYY-MM-DD`, `timezone` null),
-- a floating datetime (`date` is `YYYY-MM-DDTHH:MM:SS`, already in the user's
-- own timezone, `timezone` null) and a datetime with a fixed zone (`date` is
-- `YYYY-MM-DDTHH:MM:SSZ` stored in UTC, `timezone` naming the zone it was set
-- in). `date` is the field read here: `string` is prose for a human and
-- `timezone` only repeats what the trailing `Z` already says.
--
-- Everything is compared as local wall-clock text, so the clock is two values:
-- the stamp local time reads now, and how far local time is ahead of UTC. A
-- spec hands both in, which is what keeps its answer from depending on when or
-- where the spec runs.

local M = {}

local SECONDS_PER_DAY = 86400

--- Days between 1970-01-01 and a civil date, and the reverse. Plain arithmetic
--- rather than `os.time`, because that reads the machine's own timezone and the
--- only offset that may enter this module is the one the clock carried in.
---@param year integer
---@param month integer
---@param day integer
---@return integer
local function days_from_civil(year, month, day)
  local y = month <= 2 and year - 1 or year
  local era = math.floor(y / 400)
  local year_of_era = y - era * 400
  local day_of_year = math.floor((153 * (month + (month > 2 and -3 or 9)) + 2) / 5) + day - 1
  local day_of_era = year_of_era * 365 + math.floor(year_of_era / 4) - math.floor(year_of_era / 100) + day_of_year

  return era * 146097 + day_of_era - 719468
end

---@param days integer
---@return integer year
---@return integer month
---@return integer day
local function civil_from_days(days)
  local z = days + 719468
  local era = math.floor(z / 146097)
  local day_of_era = z - era * 146097
  local year_of_era = math.floor(
    (day_of_era - math.floor(day_of_era / 1460) + math.floor(day_of_era / 36524) - math.floor(day_of_era / 146096))
      / 365
  )
  local year = year_of_era + era * 400
  local day_of_year = day_of_era - (365 * year_of_era + math.floor(year_of_era / 4) - math.floor(year_of_era / 100))
  local month_prime = math.floor((5 * day_of_year + 2) / 153)
  local day = day_of_year - math.floor((153 * month_prime + 2) / 5) + 1
  local month = month_prime + (month_prime < 10 and 3 or -9)

  return (month <= 2 and year + 1 or year), month, day
end

--- The local wall clock now, and how far it is ahead of UTC in seconds.
---
--- Replaced wholesale in a spec, which is the only injection point: nothing
--- else here asks the machine what time it is.
---@return { stamp: string, utc_offset: integer }
function M.clock()
  local now = os.time()
  local here = os.date("*t", now)
  local utc = os.date("!*t", now)

  -- os.time(utc) re-interprets a UTC broken-down time as local, which is
  -- wrong across a daylight-saving boundary; diffing the two civil stamps
  -- directly avoids that round trip.
  local here_seconds = days_from_civil(here.year, here.month, here.day) * SECONDS_PER_DAY
    + here.hour * 3600
    + here.min * 60
    + here.sec
  local utc_seconds = days_from_civil(utc.year, utc.month, utc.day) * SECONDS_PER_DAY
    + utc.hour * 3600
    + utc.min * 60
    + utc.sec

  return { stamp = os.date("%Y-%m-%dT%H:%M:%S", now), utc_offset = here_seconds - utc_seconds }
end

--- A stamp moved by a number of seconds, in wall-clock terms.
---@param year integer
---@param month integer
---@param day integer
---@param hour integer
---@param minute integer
---@param second integer
---@param seconds integer
---@return string
local function shifted(year, month, day, hour, minute, second, seconds)
  local total = days_from_civil(year, month, day) * SECONDS_PER_DAY + hour * 3600 + minute * 60 + second + seconds
  local days = math.floor(total / SECONDS_PER_DAY)
  local rest = total - days * SECONDS_PER_DAY
  local y, m, d = civil_from_days(days)

  return ("%04d-%02d-%02dT%02d:%02d:%02d"):format(
    y,
    m,
    d,
    math.floor(rest / 3600),
    math.floor(rest % 3600 / 60),
    rest % 60
  )
end

--- The local wall-clock stamp a due object names, and whether it carries a time
--- of day.
---
--- A JSON null decodes to `vim.NIL`, which is truthy, so a task with no due date
--- has to be recognised by the type of its `due` rather than by falling back
--- with `or`. That is the common case: most tasks have no due date at all.
---@param task table
---@param clock { stamp: string, utc_offset: integer }
---@return string? stamp `YYYY-MM-DD` for a full-day date, `YYYY-MM-DDTHH:MM:SS` for a time
---@return boolean timed
function M.stamp_of(task, clock)
  local due = task.due
  if type(due) ~= "table" then
    return nil, false
  end

  local date = due.date
  if type(date) ~= "string" then
    return nil, false
  end

  local day = date:match("^(%d%d%d%d%-%d%d%-%d%d)$")
  if day then
    return day, false
  end

  local year, month, monthday, hour, minute, second = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
  if not year then
    return nil, false
  end

  -- A trailing Z is the fixed-zone shape, stored in UTC; anything else is
  -- floating and already reads in the user's own timezone.
  local offset = date:match("Z$") and clock.utc_offset or 0

  return shifted(
    tonumber(year),
    tonumber(month),
    tonumber(monthday),
    tonumber(hour),
    tonumber(minute),
    tonumber(second),
    offset
  ),
    true
end

--- Where a task stands against the clock.
---
--- `overdue` is the moment its time has passed, which for a task due today at
--- 09:00 is any time from 09:00 on. A full-day task carries no time, so it is
--- `due` for the whole of its day and `overdue` only once the day is over.
---@param task table
---@param clock { stamp: string, utc_offset: integer }
---@return "none"|"overdue"|"due"|"later" state
---@return boolean timed
---@return string? stamp
function M.classify(task, clock)
  local stamp, timed = M.stamp_of(task, clock)
  if not stamp then
    return "none", false, nil
  end

  local today = clock.stamp:sub(1, 10)
  local day = stamp:sub(1, 10)

  if day < today then
    return "overdue", timed, stamp
  elseif day > today then
    return "later", timed, stamp
  end

  -- Both ISO 8601, so the text sorts the way the instants do.
  if timed and stamp <= clock.stamp then
    return "overdue", timed, stamp
  end

  return "due", timed, stamp
end

return M
