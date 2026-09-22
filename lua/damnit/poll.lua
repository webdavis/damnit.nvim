-- The count behind `status()`, the timer that keeps it fresh, and the due
-- reminder that rides on the same fetch.
--
-- `status()` is called on every redraw, so it does no work: it returns a string
-- that was built the last time an answer arrived. One timer does the fetching,
-- and both the count and the reminders read the objects it stored, so there is
-- one poller in this plugin and one source of truth behind both features.
--
-- Reading "has its time passed" is done here rather than by the query: the
-- count and the reminder have to agree, and a dam query answers by date alone.

local M = {}

local due = require("damnit.due")
local message = require("damnit.message")

--- The query the refresh runs. Every object either feature has anything to say
--- about, and nothing else.
---
--- `!done` is load-bearing: `due:today` matches a completed task as readily as
--- an open one, so without it a task just finished keeps its place in the
--- count. `--no-pull` is what lets a poll running every minute promise that it
--- reaches no remote.
M.QUERY = "!done & (due:today | overdue)"

--- The objects the last successful fetch returned.
---@type table[]
local objects = {}

--- The string `status()` hands back, rebuilt whenever an answer arrives.
---
--- Empty until the first fetch has finished, and empty again whenever nothing
--- is due. One answer covers both, because a statusline component that returns
--- an empty string draws nothing, which is what no news looks like.
local line = ""

--- The due instants already announced, as `<oid>@<stamp>`. Keyed by the instant
--- and not by the object, so the next iteration of a recurring task and a task
--- moved to a new time are both announced again.
---@type table<string, boolean>
local announced = {}

--- Whether a fetch has finished since the timer started. The first one only
--- records what is already overdue: a task whose time passed while Neovim was
--- closed is history, and opening the editor at five o'clock should not replay
--- the morning.
local seeded = false

---@type uv.uv_timer_t?
local timer = nil

--- Whether the `VimLeavePre` autocmd has been registered. Checked instead of
--- registering on every `M.start()`, so a stop and start cycle does not leave a
--- second one behind to call `M.stop` twice.
local autocmd_registered = false

--- One object's `task` sub-table, which is where dam puts `due`.
---@param object table
---@return table
local function task_of(object)
  local task = object.task

  return type(task) == "table" and task or {}
end

--- The counts as they stood at the last fetch.
---@return { due: integer, overdue: integer }
function M.counts()
  local clock = due.clock()
  local counts = { due = 0, overdue = 0 }

  for _, object in ipairs(objects) do
    local where = due.classify(task_of(object), clock)
    if where == "due" or where == "overdue" then
      counts[where] = counts[where] + 1
    end
  end

  return counts
end

---@param counts { due: integer, overdue: integer }
---@return string
local function render(counts)
  local parts = {}

  if counts.due > 0 then
    parts[#parts + 1] = counts.due .. " due"
  end

  if counts.overdue > 0 then
    parts[#parts + 1] = counts.overdue .. " overdue"
  end

  return table.concat(parts, ", ")
end

--- Announce every task whose time has come since the last fetch, once each.
---@param clock { stamp: string, utc_offset: integer }
local function announce(clock)
  if not require("damnit").options.reminders then
    return
  end

  -- Rebuilt from the objects in hand, so the set cannot grow across a session
  -- of completed and rescheduled tasks.
  local still_open = {}

  for _, object in ipairs(objects) do
    local where, timed, stamp = due.classify(task_of(object), clock)

    -- A whole-day task has no moment to come due at, so it is never announced.
    if timed and where == "overdue" then
      local key = tostring(object.oid) .. "@" .. stamp
      still_open[key] = true

      if not announced[key] and seeded then
        message.say(("due now: %s"):format(tostring(object.subject)))
      end
    end
  end

  announced = still_open
  seeded = true
end

--- Take one fetch's answer: store it, rebuild the string, announce what came
--- due. The only way objects enter this module, so a spec drives it directly.
---@param fetched table[]?
---@param err damnit.Error?
function M.apply(fetched, err)
  if err then
    objects = {}
    line = "dam !"

    return
  end

  objects = fetched or {}
  line = render(M.counts())

  announce(due.clock())
end

--- Ask dam for the objects both features read.
---
--- Quiet: a background fetch that failed says so in the statusline, and a store
--- that will not open would otherwise raise the same warning every tick.
function M.refresh()
  local queue = require("damnit.queue")

  -- A poll queued behind a running call answers about a store that call is
  -- still changing, and arrives after the count it reports has gone stale. The
  -- running operation already owns the statusline slot.
  if queue.running() then
    return
  end

  queue.submit({
    args = { "ls", M.QUERY, "--no-pull", "--json" },
    label = "ls",
    background = true,
    on_done = function(data, err)
      M.apply(data and data.objects, err)
    end,
  })
end

--- Start the one timer, if it is not already running.
---
--- Called by the first `status()` and by `setup` when reminders are on, so a
--- statusline that never mentions this plugin and a configuration that never
--- turns reminders on cost nothing.
function M.start()
  -- A redraw between VimLeavePre and exit would otherwise undo the stop that
  -- autocmd just did.
  if vim.v.exiting ~= vim.NIL then
    return
  end

  if timer then
    return
  end

  local interval = math.max(tonumber(require("damnit").options.refresh_interval) or 60, 5) * 1000

  timer = vim.uv.new_timer()
  timer:start(0, interval, vim.schedule_wrap(M.refresh))

  if not autocmd_registered then
    -- A timer that outlived the editor would keep the loop alive on `:qa`.
    vim.api.nvim_create_autocmd("VimLeavePre", { callback = M.stop, desc = "dam: stop the refresh timer" })
    autocmd_registered = true
  end
end

--- Stop it, and forget that a fetch ever happened. Nothing is keeping the count
--- fresh once the timer is gone, so the count goes with it and `status()` is
--- empty again rather than frozen at its last reading.
function M.stop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end

  objects = {}
  line = ""
  announced = {}
  seeded = false
end

--- Whether the timer is running, which is how the exit behaviour is observed.
---@return boolean
function M.running()
  return timer ~= nil
end

--- The statusline string, which is why nothing here fetches, waits or counts: a
--- component is evaluated on every redraw.
---
--- A failed fetch reads `dam !`, because a count left standing after the store
--- stopped answering is worse than no count at all.
---@return string
function M.status()
  M.start()

  local running = require("damnit.queue").foreground()
  if running then
    return ("dam: %s %.1fs"):format(running.label, running.elapsed)
  end

  return line
end

return M
