-- The statusline string, the one poller behind it, and the due reminder.
--
-- Nothing here reaches Todoist: the fetch is replaced with a double that hands
-- back whatever the case wants, and the clock is replaced too, so no case
-- depends on the hour it runs at. Nothing sleeps either: an answer arrives when
-- the case says it does.

local client = require("todoist.client")
local due = require("todoist.due")
local status = require("todoist.status")
local todoist = require("todoist")

local NOON = "2026-09-17T12:00:00"

---@param id string
---@param date any
---@return table
local function task(id, date)
  return { id = id, content = "task " .. id, due = { date = date, string = "today" } }
end

--- Run `body` with the clock stopped at `stamp`, the fetch faked and every
--- notification collected. The module's own state is dropped on the way in and
--- on the way out, so one case is never another case's starting point.
---@param opts { stamp: string?, reminders: boolean? }
---@param body fun(fetch: fun(tasks: table[]?, err: table?)): any
---@return any result
---@return string[] notifications
local function with(opts, body)
  local options = todoist.options
  local real_clock = due.clock
  local real_collect = client.collect
  local real_notify = vim.notify

  status.stop()

  local stamp = opts.stamp or NOON
  due.clock = function()
    return { stamp = stamp, utc_offset = 0 }
  end

  todoist.options = vim.tbl_deep_extend("force", options, { reminders = opts.reminders or false })

  -- The double holds the callback instead of answering, so the case decides
  -- when an answer arrives and what it is.
  local answer = nil
  client.collect = function(_, callback)
    answer = callback
  end

  local notifications = {}
  vim.notify = function(message)
    table.insert(notifications, message)
  end

  local function fetch(tasks, err)
    status.refresh()
    assert(answer, "nothing asked for a fetch")
    answer(tasks, err)
  end

  local ok, result = pcall(body, fetch)

  status.stop()
  todoist.options = options
  due.clock = real_clock
  client.collect = real_collect
  vim.notify = real_notify

  if not ok then
    error(result, 0)
  end

  return result, notifications
end

return {
  ["nothing is on the statusline before the first fetch has finished"] = function()
    local line = with({}, function()
      return status.status()
    end)
    assert(line == "", line)
  end,

  ["nothing is on it when nothing is due either"] = function()
    local line = with({}, function(fetch)
      fetch({ task("1", "2026-09-19") })
      return status.status()
    end)
    assert(line == "", line)
  end,

  ["one task due today reads as one"] = function()
    local line = with({}, function(fetch)
      fetch({ task("1", "2026-09-17") })
      return status.status()
    end)
    assert(line == "1 due", line)
  end,

  ["one task overdue reads as overdue alone"] = function()
    local line = with({}, function(fetch)
      fetch({ task("1", "2026-09-16") })
      return status.status()
    end)
    assert(line == "1 overdue", line)
  end,

  ["both kinds read as both, due first"] = function()
    local line = with({}, function(fetch)
      fetch({
        task("1", "2026-09-17"),
        task("2", "2026-09-17T15:00:00"),
        task("3", "2026-09-17T09:00:00"),
        task("4", "2026-09-16"),
      })
      return status.status()
    end)
    assert(line == "2 due, 2 overdue", line)
  end,

  ["a task with no due date is counted as neither"] = function()
    local line = with({}, function(fetch)
      fetch({ { id = "1", content = "no date", due = vim.NIL }, task("2", "2026-09-17") })
      return status.status()
    end)
    assert(line == "1 due", line)
  end,

  ["a failed fetch says so rather than leaving the last count standing"] = function()
    local line = with({}, function(fetch)
      fetch({ task("1", "2026-09-17") })
      fetch(nil, { kind = "network", message = "no route to host" })
      return status.status()
    end)
    assert(line == "todoist !", line)
  end,

  ["a failed fetch clears M.counts() too, not just the statusline"] = function()
    local counts = with({}, function(fetch)
      fetch({ task("1", "2026-09-17") })
      fetch(nil, { kind = "network", message = "no route to host" })
      return status.counts()
    end)
    assert(counts.due == 0 and counts.overdue == 0, vim.inspect(counts))
  end,

  ["a token that will not resolve reads the same way"] = function()
    local line, notifications = with({}, function(fetch)
      fetch(nil, { kind = "token", message = "no token_command or token_env is set" })
      return status.status()
    end)
    assert(line == "todoist !", line)
    assert(#notifications == 0, "a background fetch must not raise a warning of its own")
  end,

  ["the reminder is off unless it is turned on"] = function()
    local _, notifications = with({ reminders = false }, function(fetch)
      fetch({ task("1", "2026-09-17T09:00:00") })
      fetch({ task("1", "2026-09-17T09:00:00") })
    end)
    assert(#notifications == 0, table.concat(notifications, " / "))
  end,

  ["a task that came due while the editor was closed is not announced"] = function()
    local _, notifications = with({ reminders = true }, function(fetch)
      fetch({ task("1", "2026-09-17T09:00:00") })
    end)
    assert(#notifications == 0, table.concat(notifications, " / "))
  end,

  ["a task that comes due while the editor is open is announced once"] = function()
    local _, notifications = with({ reminders = true, stamp = "2026-09-17T08:00:00" }, function(fetch)
      local pending = { task("1", "2026-09-17T09:00:00") }

      fetch(pending)

      due.clock = function()
        return { stamp = "2026-09-17T09:05:00", utc_offset = 0 }
      end

      fetch(pending)
      fetch(pending)
    end)

    assert(#notifications == 1, table.concat(notifications, " / "))
    assert(notifications[1]:match("task 1"), notifications[1])
  end,

  ["a task completed before its time is never announced"] = function()
    local _, notifications = with({ reminders = true, stamp = "2026-09-17T08:00:00" }, function(fetch)
      fetch({ task("1", "2026-09-17T09:00:00") })

      due.clock = function()
        return { stamp = "2026-09-17T09:05:00", utc_offset = 0 }
      end

      -- Completing it takes it out of the open tasks the fetch answers with.
      fetch({})
    end)

    assert(#notifications == 0, table.concat(notifications, " / "))
  end,

  ["a full-day task due today is never announced, having no time to come due at"] = function()
    local _, notifications = with({ reminders = true, stamp = "2026-09-17T08:00:00" }, function(fetch)
      fetch({ task("1", "2026-09-17") })
      fetch({ task("1", "2026-09-17") })
    end)

    assert(#notifications == 0, table.concat(notifications, " / "))
  end,

  ["the first statusline call starts the one timer, and the second adds none"] = function()
    with({}, function()
      assert(not status.running())
      status.status()
      assert(status.running())
      status.status()
      assert(status.running())
    end)
  end,

  ["leaving the editor stops the timer"] = function()
    with({}, function()
      status.status()
      assert(status.running())

      vim.api.nvim_exec_autocmds("VimLeavePre", {})
      assert(not status.running(), "a timer that outlives the editor holds the loop open")
    end)
  end,

  ["stopping and restarting the timer registers the VimLeavePre autocmd only once"] = function()
    with({}, function()
      status.status()
      status.stop()
      status.status()
      status.stop()
      status.status()

      local count = 0
      for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = "VimLeavePre" })) do
        if autocmd.desc == "Todoist: stop the refresh timer" then
          count = count + 1
        end
      end

      assert(count == 1, ("found %d, wanted 1"):format(count))
    end)
  end,
}
