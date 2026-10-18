local M = {}

function M.new()
  local read = {}
  local waiting = nil

  function read.wait(callback, start)
    if waiting then
      waiting[#waiting + 1] = callback
      return
    end

    waiting = { callback }
    start()
  end

  function read.settle(...)
    local callbacks = waiting or {}
    waiting = nil

    for _, callback in ipairs(callbacks) do
      callback(...)
    end
  end

  return read
end

return M
