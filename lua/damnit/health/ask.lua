local M = {}

M.DEADLINE_MS = 20000

local WAIT_INTERVAL_MS = 20

local function settle(start)
  local boxed_answer = nil

  start(function(value, err)
    boxed_answer = { value = value, err = err }
  end)

  local finished = vim.wait(M.DEADLINE_MS, function()
    return boxed_answer ~= nil
  end, WAIT_INTERVAL_MS)

  if not finished then
    return false
  end

  return true, boxed_answer.value, boxed_answer.err
end

function M.call(app, args)
  return settle(function(done)
    app.dam.call(args, nil, done)
  end)
end

return M
