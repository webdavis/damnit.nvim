local M = {}

local civil = require("damnit.civil")

local function civil_seconds(stamp)
  return civil.seconds_from_civil(stamp.year, stamp.month, stamp.day, stamp.hour, stamp.min, stamp.sec)
end

local function utc_offset_by_diffing_civil_stamps(now)
  return civil_seconds(os.date("*t", now)) - civil_seconds(os.date("!*t", now))
end

function M.clock()
  local now = os.time()

  return { stamp = os.date("%Y-%m-%dT%H:%M:%S", now), utc_offset = utc_offset_by_diffing_civil_stamps(now) }
end

local function shifted(year, month, day, hour, minute, second, seconds)
  local total = civil.seconds_from_civil(year, month, day, hour, minute, second) + seconds
  local days = math.floor(total / civil.SECONDS_PER_DAY)
  local rest = total - days * civil.SECONDS_PER_DAY
  local y, m, d = civil.civil_from_days(days)

  return ("%04d-%02d-%02dT%02d:%02d:%02d"):format(
    y,
    m,
    d,
    math.floor(rest / 3600),
    math.floor(rest % 3600 / 60),
    rest % 60
  )
end

local function offset_of(suffix)
  local without_fraction = suffix:gsub("^%.%d+", "")

  if without_fraction:match("^[Zz]") then
    return 0
  end

  local sign, hours, minutes = without_fraction:match("^([%+%-])(%d%d):(%d%d)")
  if not sign then
    return nil
  end

  local seconds = tonumber(hours) * 3600 + tonumber(minutes) * 60

  return sign == "-" and -seconds or seconds
end

local function seconds_to_local_time(offset, clock)
  local already_local_wall_clock = offset == nil
  if already_local_wall_clock then
    return 0
  end

  return clock.utc_offset - offset
end

function M.stamp_of(task, clock)
  local value = task.due
  if type(value) ~= "string" then
    return nil, false
  end

  local day = value:match("^(%d%d%d%d%-%d%d%-%d%d)$")
  if day then
    return day, false
  end

  local year, month, monthday, hour, minute, second, suffix =
    value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)(.*)$")
  if not year then
    return nil, false
  end

  local offset = offset_of(suffix)

  return shifted(
    tonumber(year),
    tonumber(month),
    tonumber(monthday),
    tonumber(hour),
    tonumber(minute),
    tonumber(second),
    seconds_to_local_time(offset, clock)
  ),
    true
end

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

  local time_has_passed = timed and stamp <= clock.stamp
  if time_has_passed then
    return "overdue", timed, stamp
  end

  return "due", timed, stamp
end

return M
