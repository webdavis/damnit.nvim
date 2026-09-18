-- The quick edits: what each key sends, what gates the delete, how the priority
-- cycle wraps, and what `u` reverses.
--
-- The client is a stub here, so no curl runs and no port is opened: these cases
-- are about which call a key makes and with what. The wire itself is pinned in
-- quick_edit_loopback_spec.

local quick_edit = require("todoist.quick_edit")

local TASK = { id = "6XGg", content = "Buy milk", priority = 2, labels = { "errands" } }

local REFUSAL = { kind = "http", status = 400, message = "the API said no" }

--- Run `steps` with the client, the list and every prompt stubbed.
---
--- `env` sets what the stubs answer: `task` is what the cursor is on (false for
--- a line holding none), `fails` refuses every write, `input` is what a prompt
--- is typed into, `choose` is the index a picker is answered with, `confirm` is
--- what the yes or no question is answered with, and `labels`, `projects` and
--- `sections` are what the reads bring back.
---@param env table
---@param steps fun()
---@return table seen
local function drive(env, steps)
  local client = require("todoist.client")
  local list = require("todoist.list")

  local seen = { calls = {}, notifications = {}, rereads = 0 }

  local function record(name, argument, body)
    table.insert(seen.calls, { name = name, argument = argument, body = body })
  end

  local function wrote(callback)
    callback(nil, env.fails and REFUSAL or nil)
  end

  local stubs = {
    close_task = function(id, callback)
      record("close", id)
      wrote(callback)
    end,
    reopen_task = function(id, callback)
      record("reopen", id)
      wrote(callback)
    end,
    delete_task = function(id, callback)
      record("delete", id)
      wrote(callback)
    end,
    update_task = function(id, fields, callback)
      record("update", id, fields)
      wrote(callback)
    end,
    move_task = function(id, destination, callback)
      record("move", id, destination)
      wrote(callback)
    end,
    quick_add = function(line, callback)
      record("quick_add", line)
      callback({ content = line }, env.fails and REFUSAL or nil)
    end,
    get_labels = function(callback)
      record("read_labels")
      callback(env.labels or {})
    end,
    get_projects = function(callback)
      record("read_projects")
      callback(env.projects or {})
    end,
    get_sections = function(callback)
      record("read_sections")
      callback(env.sections or {})
    end,
  }

  local reals = { notify = vim.notify, ui = vim.ui, confirm = vim.fn.confirm }
  for name in pairs(stubs) do
    reals[name] = client[name]
    client[name] = stubs[name]
  end

  local real_under_cursor, real_refresh = list.task_under_cursor, list.refresh
  list.task_under_cursor = function()
    if env.task == false then
      return nil
    end

    return env.task or TASK
  end
  list.refresh = function()
    seen.rereads = seen.rereads + 1
  end

  vim.notify = function(message)
    table.insert(seen.notifications, message)
  end
  vim.ui = {
    input = function(_, on_confirm)
      on_confirm(env.input)
    end,
    select = function(items, _, on_choice)
      if not env.choose then
        return on_choice(nil)
      end

      seen.offered = items
      on_choice(items[env.choose], env.choose)
    end,
  }
  vim.fn.confirm = function()
    return env.confirm or 1
  end

  quick_edit.forget()
  local ok, err = pcall(steps)

  for name in pairs(stubs) do
    client[name] = reals[name]
  end
  list.task_under_cursor, list.refresh = real_under_cursor, real_refresh
  vim.notify, vim.ui, vim.fn.confirm = reals.notify, reals.ui, reals.confirm

  assert(ok, err)

  return seen
end

---@param seen table
---@param expected string[]
local function called(seen, expected)
  local names = {}
  for _, call in ipairs(seen.calls) do
    table.insert(names, call.name)
  end

  assert(table.concat(names, ",") == table.concat(expected, ","), vim.inspect(seen.calls))
end

return {
  ["x completes the task under the cursor and re-reads the view"] = function()
    local seen = drive({}, quick_edit.complete)

    called(seen, { "close" })
    assert(seen.calls[1].argument == "6XGg", vim.inspect(seen.calls))
    assert(seen.rereads == 1, tostring(seen.rereads))
  end,

  ["X reopens the task under the cursor"] = function()
    local seen = drive({}, quick_edit.reopen)

    called(seen, { "reopen" })
    assert(seen.calls[1].argument == "6XGg", vim.inspect(seen.calls))
  end,

  ["a key on a line holding no task sends nothing"] = function()
    local seen = drive({ task = false }, quick_edit.complete)

    called(seen, {})
  end,

  ["dd deletes once the confirm is answered yes"] = function()
    local seen = drive({ confirm = 1 }, quick_edit.delete)

    called(seen, { "delete" })
    assert(seen.calls[1].argument == "6XGg", vim.inspect(seen.calls))
  end,

  ["dd sends nothing when the confirm is declined"] = function()
    local seen = drive({ confirm = 2 }, quick_edit.delete)

    called(seen, {})
    assert(seen.rereads == 0, tostring(seen.rereads))
  end,

  ["p cycles the priority one step up in urgency"] = function()
    local seen = drive({}, quick_edit.cycle_priority)

    called(seen, { "update" })
    assert(vim.deep_equal(seen.calls[1].body, { priority = 3 }), vim.inspect(seen.calls))
  end,

  ["p wraps from the most urgent back to no priority"] = function()
    local seen = drive({ task = vim.tbl_extend("force", TASK, { priority = 4 }) }, quick_edit.cycle_priority)

    assert(vim.deep_equal(seen.calls[1].body, { priority = 1 }), vim.inspect(seen.calls))
  end,

  ["p treats a task with no priority as the lowest"] = function()
    local seen = drive({ task = { id = "6XGg", content = "Buy milk" } }, quick_edit.cycle_priority)

    assert(vim.deep_equal(seen.calls[1].body, { priority = 2 }), vim.inspect(seen.calls))
  end,

  ["s sends the line typed as the due string, and nothing when it is blank"] = function()
    local seen = drive({ input = "next mon" }, quick_edit.schedule)

    called(seen, { "update" })
    assert(vim.deep_equal(seen.calls[1].body, { due_string = "next mon" }), vim.inspect(seen.calls))

    assert(#drive({ input = "   " }, quick_edit.schedule).calls == 0)
  end,

  ["l writes the whole label set with the chosen one flipped on"] = function()
    local seen = drive({
      labels = { { name = "home", order = 1 }, { name = "errands", order = 2 } },
      choose = 1,
    }, quick_edit.labels)

    called(seen, { "read_labels", "update" })
    assert(vim.deep_equal(seen.calls[2].body, { labels = { "home", "errands" } }), vim.inspect(seen.calls))
  end,

  ["l takes a label off the task it is on"] = function()
    local seen = drive({
      labels = { { name = "home", order = 1 }, { name = "errands", order = 2 } },
      choose = 2,
    }, quick_edit.labels)

    assert(vim.deep_equal(seen.calls[2].body, { labels = {} }), vim.inspect(seen.calls))
  end,

  ["a label the API answered without a name does not break the picker"] = function()
    local seen = drive({
      labels = { { name = vim.NIL, order = 1 }, { name = "home", order = 2 } },
      choose = 1,
    }, quick_edit.labels)

    -- The nameless one is gone and the named ones are all still offered: the
    -- task's own stray label comes last, so it can be taken off.
    assert(#seen.offered == 2, vim.inspect(seen.offered))
    assert(seen.offered[1].name == "home", vim.inspect(seen.offered))
    assert(vim.deep_equal(seen.calls[2].body, { labels = { "home", "errands" } }), vim.inspect(seen.calls))
  end,

  ["m moves the task to the destination chosen"] = function()
    local seen = drive({
      projects = { { id = "1", name = "Errands" } },
      sections = { { id = "9", project_id = "1", name = "Saturday" } },
      choose = 2,
    }, quick_edit.move)

    called(seen, { "read_projects", "read_sections", "move" })
    assert(vim.deep_equal(seen.calls[3].body, { section_id = "9" }), vim.inspect(seen.calls))
    assert(seen.offered[1].label == "Errands", vim.inspect(seen.offered))
    assert(seen.offered[2].label == "  Saturday", vim.inspect(seen.offered))
  end,

  ["a sends the whole Quick Add line for Todoist to parse"] = function()
    local seen = drive({ input = "Pay rent tomorrow 9am p1 #Finances @home" }, quick_edit.add)

    called(seen, { "quick_add" })
    assert(seen.calls[1].argument == "Pay rent tomorrow 9am p1 #Finances @home", vim.inspect(seen.calls))
    assert(seen.rereads == 1, tostring(seen.rereads))
  end,

  ["u reopens the task the last x completed"] = function()
    local seen = drive({}, function()
      quick_edit.complete()
      quick_edit.undo()
    end)

    called(seen, { "close", "reopen" })
    assert(seen.calls[2].argument == "6XGg", vim.inspect(seen.calls))
  end,

  ["u completes the task the last X reopened"] = function()
    local seen = drive({}, function()
      quick_edit.reopen()
      quick_edit.undo()
    end)

    called(seen, { "reopen", "close" })
  end,

  ["a write that is not x or X leaves the remembered undo alone"] = function()
    local seen = drive({}, function()
      quick_edit.complete()
      quick_edit.cycle_priority()
      quick_edit.undo()
    end)

    called(seen, { "close", "update", "reopen" })
    assert(seen.calls[3].argument == "6XGg", vim.inspect(seen.calls))
  end,

  ["u is one level deep, so a second one has nothing left to reverse"] = function()
    local seen = drive({}, function()
      quick_edit.complete()
      quick_edit.undo()
      quick_edit.undo()
    end)

    called(seen, { "close", "reopen" })
    assert(seen.notifications[#seen.notifications]:find("nothing to undo", 1, true), vim.inspect(seen.notifications))
  end,

  ["u after a write that is neither says there is nothing to undo"] = function()
    local seen = drive({ input = "tomorrow" }, function()
      quick_edit.schedule()
      quick_edit.undo()
    end)

    called(seen, { "update" })
    assert(seen.notifications[#seen.notifications]:find("nothing to undo", 1, true), vim.inspect(seen.notifications))
  end,

  ["a refused reversal keeps it to undo and re-reads the view"] = function()
    local client = require("todoist.client")
    local refused = drive({}, function()
      quick_edit.complete()
      -- The complete landed; the reversal is what the API refuses, which is the
      -- case the undo has to survive.
      local real = client.reopen_task
      client.reopen_task = function(id, callback)
        real(id, function()
          callback(nil, REFUSAL)
        end)
      end
      quick_edit.undo()
      client.reopen_task = real
      quick_edit.undo()
    end)

    called(refused, { "close", "reopen", "reopen" })
    assert(refused.rereads == 3, tostring(refused.rereads))
  end,
}
