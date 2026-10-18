local M = {}

local due = require("damnit.due")
local verbs = require("damnit.dam.verbs")

M.QUERY = "!done & (due:today | overdue)"

local last_fetched_objects = {}

local built_status = ""

local announced_instants = {}

local past_first_fetch = false

local timer = nil

local DEFAULT_REFRESH_SECONDS = 60

local MIN_REFRESH_SECONDS = 5

local stop_on_exit_registered = false

local function task_of(object)
  local task = object.task

  return type(task) == "table" and task or {}
end

function M.counts()
  local clock = due.clock()
  local counts = { due = 0, overdue = 0 }

  for _, object in ipairs(last_fetched_objects) do
    local where = due.classify(task_of(object), clock)
    if where == "due" or where == "overdue" then
      counts[where] = counts[where] + 1
    end
  end

  return counts
end

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

local function instant_key(object, stamp)
  return tostring(object.oid) .. "@" .. stamp
end

local function announce(app, clock)
  if not app.options.reminders then
    return
  end

  local instants_still_overdue = {}

  for _, object in ipairs(last_fetched_objects) do
    local where, timed, stamp = due.classify(task_of(object), clock)

    local came_due_at_a_moment = timed and where == "overdue"
    if came_due_at_a_moment then
      local key = instant_key(object, stamp)
      instants_still_overdue[key] = true

      if not announced_instants[key] and past_first_fetch then
        app.say.info(("due now: %s"):format(tostring(object.subject)))
      end
    end
  end

  announced_instants = instants_still_overdue
  past_first_fetch = true
end

function M.apply(app, fetched, err)
  if err then
    last_fetched_objects = {}
    built_status = "dam !"

    return
  end

  last_fetched_objects = fetched or {}
  built_status = render(M.counts())

  announce(app, due.clock())
end

function M.refresh(app)
  local queue = app.queue

  local another_call_holds_the_store = queue.running()
  if another_call_holds_the_store then
    return
  end

  queue.submit({
    args = verbs.ls(M.QUERY, true),
    label = "ls",
    background = true,
    on_done = function(data, err)
      M.apply(app, data and data.objects, err)
    end,
  })
end

function M.start(app)
  local editor_is_exiting = vim.v.exiting ~= vim.NIL
  if editor_is_exiting then
    return
  end

  if timer then
    return
  end

  local seconds = math.max(tonumber(app.options.refresh_interval) or DEFAULT_REFRESH_SECONDS, MIN_REFRESH_SECONDS)
  local interval = seconds * 1000

  timer = vim.uv.new_timer()
  timer:start(
    0,
    interval,
    vim.schedule_wrap(function()
      M.refresh(app)
    end)
  )

  if not stop_on_exit_registered then
    vim.api.nvim_create_autocmd("VimLeavePre", { callback = M.stop, desc = "dam: stop the refresh timer" })
    stop_on_exit_registered = true
  end
end

function M.stop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end

  last_fetched_objects = {}
  built_status = ""
  announced_instants = {}
  past_first_fetch = false
end

function M.running()
  return timer ~= nil
end

function M.status(app)
  M.start(app)

  local running = app.queue.foreground()
  if running then
    return ("dam: %s %.1fs"):format(running.label, running.elapsed)
  end

  return built_status
end

return M
