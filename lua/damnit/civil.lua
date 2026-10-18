local M = {}

M.SECONDS_PER_DAY = 86400

function M.days_from_civil(year, month, day)
  local y = month <= 2 and year - 1 or year
  local era = math.floor(y / 400)
  local year_of_era = y - era * 400
  local day_of_year = math.floor((153 * (month + (month > 2 and -3 or 9)) + 2) / 5) + day - 1
  local day_of_era = year_of_era * 365 + math.floor(year_of_era / 4) - math.floor(year_of_era / 100) + day_of_year

  return era * 146097 + day_of_era - 719468
end

function M.civil_from_days(days)
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

function M.seconds_from_civil(year, month, day, hour, minute, second)
  return M.days_from_civil(year, month, day) * M.SECONDS_PER_DAY + hour * 3600 + minute * 60 + second
end

return M
