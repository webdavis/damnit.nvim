-- The count behind `status()`, the timer that keeps it fresh, and the due
-- reminder that rides on the same fetch.
--
-- `status()` is called on every redraw, so it does no work: it returns a string
-- that was built the last time an answer arrived. One timer does the fetching,
-- and both the count and the reminders read the tasks it stored, so there is one
-- poller in this plugin and one source of truth behind both features.
--
-- The fetch asks Todoist for `overdue | today`, which is every task either
-- feature has anything to say about, and the reading of those tasks is done
-- here rather than by the API: the count and the reminder have to agree, and a
-- filter cannot answer "has its time passed".

local M = {}

local client = require("todoist.client")
local due = require("todoist.due")

--- The Todoist filter the refresh runs. Both features only ever count or
--- announce something from today or earlier.
local FILTER = "overdue | today"

--- The tasks the last successful fetch returned.
---@type table[]
local tasks = {}

--- What the last fetch did. `cold` is "no fetch has finished yet", which is the
--- state a statusline draws before the first answer and the reason the empty
--- string is what it gets.
---@type "cold"|"ok"|"failed"
local state = "cold"

--- The string `status()` hands back, rebuilt whenever an answer arrives.
local line = ""

--- The due instants already announced, as `<task id>@<stamp>`. Keyed by the
--- instant and not by the task, so the next iteration of a recurring task and a
--- task moved to a new time are both announced again.
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
--- registering on every `M.start()`, so a stop/start cycle does not leave a
--- second one behind to call `M.stop` twice.
local autocmd_registered = false

--- The counts as they stood at the last fetch.
---@return { due: integer, overdue: integer }
function M.counts()
  local clock = due.clock()
  local counts = { due = 0, overdue = 0 }

  for _, task in ipairs(tasks) do
    local where = due.classify(task, clock)
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
  if not require("todoist").options.reminders then
    return
  end

  -- Rebuilt from the tasks in hand, so the set cannot grow across a session of
  -- completed and rescheduled tasks.
  local still_open = {}

  for _, task in ipairs(tasks) do
    local where, timed, stamp = due.classify(task, clock)

    -- A full-day task has no moment to come due at, so it is never announced.
    if timed and where == "overdue" then
      local key = tostring(task.id) .. "@" .. stamp
      still_open[key] = true

      if not announced[key] then
        if seeded then
          vim.notify(("todoist.nvim: due now: %s"):format(tostring(task.content)), vim.log.levels.INFO)
        end
      end
    end
  end

  announced = still_open
  seeded = true
end

--- Take one fetch's answer: store it, rebuild the string, announce what came
--- due. The only way tasks enter this module, so a spec drives it directly.
---@param fetched table[]?
---@param err todoist.Error?
function M.apply(fetched, err)
  if err then
    state = "failed"
    line = "todoist !"

    return
  end

  tasks = fetched or {}
  state = "ok"
  line = render(M.counts())

  announce(due.clock())
end

--- Ask Todoist for the tasks both features read.
---
--- Quiet: a background fetch that failed says so in the statusline, and a token
--- that is not configured would otherwise raise the same warning every tick.
function M.refresh()
  client.collect({ method = "GET", path = "/tasks/filter", query = { query = FILTER }, quiet = true }, M.apply)
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

  local interval = math.max(tonumber(require("todoist").options.refresh_interval) or 60, 5) * 1000

  timer = vim.uv.new_timer()
  timer:start(0, interval, vim.schedule_wrap(M.refresh))

  if not autocmd_registered then
    -- A timer that outlived the editor would keep the loop alive on `:qa`.
    vim.api.nvim_create_autocmd("VimLeavePre", { callback = M.stop, desc = "Todoist: stop the refresh timer" })
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

  tasks = {}
  state = "cold"
  line = ""
  announced = {}
  seeded = false
end

--- Whether the timer is running, which is how the exit behaviour is observed.
---@return boolean
function M.running()
  return timer ~= nil
end

--- The statusline string, which is why nothing here fetches, waits or counts:
--- a component is evaluated on every redraw.
---
--- Empty until the first fetch has finished, and empty again whenever nothing
--- is due: a statusline component that returns an empty string draws nothing,
--- which is the right answer for "no news". A failed fetch or a token that will
--- not resolve reads `todoist !`, because a count left standing after the
--- network died is worse than no count at all.
---@return string
function M.status()
  M.start()

  if state == "cold" then
    return ""
  end

  return line
end

return M
