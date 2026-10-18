local M = {}

local civil = require("damnit.civil")

local MINUTE, HOUR, DAY = 60, 3600, 86400

local function utc_epoch(timestamp)
  local fields = { timestamp:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)") }
  if #fields == 0 then
    return nil
  end

  return civil.seconds_from_civil(unpack(vim.tbl_map(tonumber, fields)))
end

function M.pulled_ago(last_pull, now)
  local at = last_pull and utc_epoch(last_pull)
  if not at then
    return last_pull and "pulled" or "never pulled"
  end

  local seconds = math.max(now - at, 0)
  if seconds < MINUTE then
    return "pulled just now"
  elseif seconds < HOUR then
    return ("pulled %dm ago"):format(seconds / MINUTE)
  elseif seconds < DAY then
    return ("pulled %dh ago"):format(seconds / HOUR)
  end

  return ("pulled %dd ago"):format(seconds / DAY)
end

return M
