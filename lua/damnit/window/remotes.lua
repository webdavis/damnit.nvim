local M = {}

local verbs = require("damnit.dam.verbs")

local remote_list_by_store = {}

function M.of(key)
  return remote_list_by_store[key]
end

function M.read_until_cached(app, key)
  if remote_list_by_store[key] ~= nil then
    return
  end

  app.queue.submit({
    args = verbs.remote_list(),
    label = "remote list",
    on_done = function(data)
      remote_list_by_store[key] = data
    end,
  })
end

function M.forget(key)
  remote_list_by_store[key] = nil
end

return M
