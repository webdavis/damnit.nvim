-- One dam process per store at a time.
--
-- This is what keeps the plugin from being a second writer against its own
-- SQLite store, and it is what makes a push and a pull impossible to overlap.
-- A read and a write share the lane: `dam status` is under 30 ms, and a fast
-- lane for reads would bring the concurrent-writer problem back the moment a
-- read pulls a stale remote.

local M = {}

local dam = require("damnit.dam")
local message = require("damnit.message")

--- How often the elapsed time is rewritten, and how long cancellation waits
--- between signals.
M.TICK_MS = 250
M.GRACE_MS = 2000

---@class damnit.Entry
---@field args string[] the subcommand and its flags, `--json` included
---@field label string what the header calls it, such as `push todoist`
---@field verb string? the word a refusal uses, such as `push`
---@field network boolean? whether this one reaches a remote
---@field on_done fun(data: table?, err: damnit.Error?)?
---@field started_at integer? vim.uv.hrtime when it began
---@field handle table?
---@field finished boolean?
---@field cancelled boolean?

---@class damnit.Lane
---@field running damnit.Entry?
---@field pending damnit.Entry[]
---@field timer uv.uv_timer_t?

---@type table<string, damnit.Lane>
local lanes = {}

---@type fun(key: string)[]
local listeners = {}

--- The store this session works against, which is the queue's key and the
--- status window's identity.
---@return string
function M.key()
  local store = require("damnit").options.store
  if type(store) == "string" and store ~= "" then
    return store
  end

  local env = vim.env.DAM_STORE
  if type(env) == "string" and env ~= "" then
    return env
  end

  return "default"
end

---@param key string
---@return damnit.Lane
local function lane_for(key)
  lanes[key] = lanes[key] or { pending = {} }

  return lanes[key]
end

---@param key string
local function tick(key)
  for _, listener in ipairs(listeners) do
    listener(key)
  end
end

---@param key string
---@param lane damnit.Lane
local function start_timer(key, lane)
  if lane.timer then
    return
  end

  lane.timer = vim.uv.new_timer()
  lane.timer:start(
    M.TICK_MS,
    M.TICK_MS,
    vim.schedule_wrap(function()
      tick(key)
    end)
  )
end

---@param key string
---@param lane damnit.Lane
local function stop_timer(key, lane)
  if not lane.timer then
    return
  end

  lane.timer:stop()
  lane.timer:close()
  lane.timer = nil

  tick(key)
end

---@param key string
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

  dam.call(entry.args, {
    label = entry.label,
    on_spawn = function(handle)
      entry.handle = handle

      -- A cancel that arrived while the handshake ran had nothing to signal, so
      -- the signal is sent here instead.
      if entry.cancelled and handle then
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

--- The network entry this lane already holds, running or waiting.
---@param lane damnit.Lane
---@return damnit.Entry?
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

--- Put one call in this store's lane.
---
--- A second network call is refused rather than queued: a queued push is a push
--- nobody asked for, against a store that has changed since they did, arriving
--- minutes later with no one watching.
---@param entry damnit.Entry
---@return boolean queued
function M.submit(entry)
  local key = M.key()
  local lane = lane_for(key)

  if entry.network then
    local busy = network_entry(lane)

    if busy then
      if busy.verb == entry.verb then
        message.warn(("%s is already running; C-c cancels it"):format(busy.label))
      else
        message.warn(("%s is running; C-c cancels it, then %s"):format(busy.label, entry.verb))
      end

      return false
    end
  end

  table.insert(lane.pending, entry)
  advance(key)

  return true
end

--- What is running in one store's lane, and how long it has been.
---@param key string?
---@return { label: string, elapsed: number, pending: integer }?
function M.running(key)
  local lane = lanes[key or M.key()]
  if not lane or not lane.running then
    return nil
  end

  return {
    label = lane.running.label,
    elapsed = (vim.uv.hrtime() - lane.running.started_at) / 1e9,
    pending = #lane.pending,
  }
end

---@param entry damnit.Entry
---@param signal string
local function escalate(entry, signal)
  local timer = vim.uv.new_timer()

  timer:start(
    M.GRACE_MS,
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

--- Stop what is running and drop what is waiting.
---@param key string?
---@return boolean cancelled
function M.cancel(key)
  key = key or M.key()
  local lane = lanes[key]

  if not lane or not lane.running then
    message.warn("nothing is running")

    return false
  end

  lane.pending = {}

  local entry = lane.running
  entry.cancelled = true

  if entry.handle then
    -- dam handles SIGINT, sets its cancellation flag and exits 3, so it gets to
    -- stop its helper and leave the store consistent.
    entry.handle:kill("sigint")
    escalate(entry, "sigterm")
  end

  return true
end

--- Call `fn` with the store key every tick while anything is running, and once
--- more when the lane empties.
---@param fn fun(key: string)
function M.on_tick(fn)
  table.insert(listeners, fn)
end

--- Drop every lane. Specs call it between cases; nothing in the plugin does.
function M.reset()
  for key, lane in pairs(lanes) do
    stop_timer(key, lane)
  end

  lanes = {}
end

return M
