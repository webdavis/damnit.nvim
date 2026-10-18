local M = {}

function M.at(epoch, body)
  local real = os.time
  rawset(os, "time", function(date)
    return date and real(date) or epoch
  end)

  local ok, err = pcall(body)
  rawset(os, "time", real)

  assert(ok, err)
end

return M
