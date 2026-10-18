local civil = require("damnit.civil")

local function civil_date(days)
  return { civil.civil_from_days(days) }
end

return {
  ["the unix epoch is day zero"] = function()
    assert(civil.days_from_civil(1970, 1, 1) == 0, civil.days_from_civil(1970, 1, 1))
  end,

  ["a leap day counts as its own day"] = function()
    assert(civil.days_from_civil(2024, 2, 29) == 19782, civil.days_from_civil(2024, 2, 29))
    assert(civil.days_from_civil(2024, 3, 1) == 19783, civil.days_from_civil(2024, 3, 1))
  end,

  ["a day before the epoch is negative"] = function()
    assert(civil.days_from_civil(1969, 12, 31) == -1, civil.days_from_civil(1969, 12, 31))
  end,

  ["a day count turns back into its date"] = function()
    assert(vim.deep_equal(civil_date(19782), { 2024, 2, 29 }), vim.inspect(civil_date(19782)))
    assert(vim.deep_equal(civil_date(-1), { 1969, 12, 31 }), vim.inspect(civil_date(-1)))
  end,

  ["seconds count from midnight of the epoch"] = function()
    local seconds = civil.seconds_from_civil(2024, 2, 29, 12, 30, 15)

    assert(seconds == 1709209815, seconds)
  end,
}
