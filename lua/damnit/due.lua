local M = {}

local SECONDS_PER_DAY = 86400

local function days_from_civil(year, month, day)
  local y = month <= 2 and year - 1 or year
  local era = math.floor(y / 400)
  local year_of_era = y - era * 400
  local day_of_year = math.floor((153 * (month + (month > 2 and -3 or 9)) + 2) / 5) + day - 1
  local day_of_era = year_of_era * 365 + math.floor(year_of_era / 4) - math.floor(year_of_era / 100) + day_of_year

  return era * 146097 + day_of_era - 719468
end

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

local function civil_seconds(stamp)
  return days_from_civil(stamp.year, stamp.month, stamp.day) * SECONDS_PER_DAY
    + stamp.hour * 3600
    + stamp.min * 60
    + stamp.sec
end

local function utc_offset_by_diffing_civil_stamps(now)
  return civil_seconds(os.date("*t", now)) - civil_seconds(os.date("!*t", now))
end

function M.clock()
  local now = os.time()

  return { stamp = os.date("%Y-%m-%dT%H:%M:%S", now), utc_offset = utc_offset_by_diffing_civil_stamps(now) }
end

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
