local M = {}

local message = require("damnit.message")

local function network_entry(lane)
  if lane.running and lane.running.network then
    return lane.running
  end

  for _, entry in ipairs(lane.pending) do
    if entry.network then
      return entry
    end
  end

  return nil
end

local function refuse_a_second_network_call(lane, entry)
  local in_lane = network_entry(lane)
  if not in_lane then
    return false
  end

  if in_lane.verb == entry.verb then
    message.warn(("%s is already running; C-c cancels it"):format(in_lane.label))
  else
    message.warn(("%s is running; C-c cancels it, then %s"):format(in_lane.label, entry.verb))
  end

  return true
end

function M.new(app, on_tick)
  local queue = { TICK_MS = 250, GRACE_MS = 2000 }

  local lanes_by_store = {}

  local function lane_for(key)
    lanes_by_store[key] = lanes_by_store[key] or { pending = {} }

    return lanes_by_store[key]
  end

  local function start_timer(key, lane)
    if lane.timer then
      return
    end

    lane.timer = vim.uv.new_timer()
    lane.timer:start(
      queue.TICK_MS,
      queue.TICK_MS,
      vim.schedule_wrap(function()
        on_tick(key)
      end)
    )
  end

  local function stop_timer(key, lane)
    if not lane.timer then
      return
    end

    lane.timer:stop()
    lane.timer:close()
    lane.timer = nil

    on_tick(key)
  end

  local function advance(key)
    local lane = lane_for(key)
    if lane.running then
      return
    end

    local entry = table.remove(lane.pending, 1)
    if not entry then
      stop_timer(key, lane)

      return
    end

    lane.running = entry
    entry.started_at = vim.uv.hrtime()
    start_timer(key, lane)

    app.dam.call(entry.args, {
      label = entry.label,
      on_spawn = function(handle)
        entry.handle = handle

        local cancelled_during_handshake = entry.cancelled and handle
        if cancelled_during_handshake then
          handle:kill("sigint")
        end
      end,
    }, function(data, err)
      entry.finished = true
      lane.running = nil

      if entry.on_done then
        entry.on_done(data, err)
      end

      advance(key)
    end)
  end

  function queue.submit(entry)
    local key = app.store
    local lane = lane_for(key)

    if entry.network and refuse_a_second_network_call(lane, entry) then
      return false
    end

    table.insert(lane.pending, entry)
    advance(key)

    return true
  end

  function queue.running(key)
    local lane = lanes_by_store[key or app.store]
    if not lane or not lane.running then
      return nil
    end

    return {
      label = lane.running.label,
      elapsed = (vim.uv.hrtime() - lane.running.started_at) / 1e9,
      pending = #lane.pending,
      background = lane.running.background,
    }
  end

  function queue.foreground(key)
    local running = queue.running(key)

    if running and running.background then
      return nil
    end

    return running
  end

  local function escalate(entry, signal)
    local timer = vim.uv.new_timer()

    timer:start(
      queue.GRACE_MS,
      0,
      vim.schedule_wrap(function()
        timer:stop()
        timer:close()

        if entry.finished or not entry.handle then
          return
        end

        entry.handle:kill(signal)

        if signal == "sigterm" then
          return escalate(entry, "sigkill")
        end

        message.warn(("%s would not stop and was killed"):format(entry.label))
      end)
    )
  end

  function queue.cancel(key)
    key = key or app.store
    local lane = lanes_by_store[key]

    if not lane or not lane.running then
      message.warn("nothing is running")

      return false
    end

    lane.pending = {}

    local entry = lane.running
    entry.cancelled = true

    if entry.handle then
      entry.handle:kill("sigint")
      escalate(entry, "sigterm")
    end

    return true
  end

  return queue
end

return M
