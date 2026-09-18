-- The task search: the lines it offers, the view it searches inside, what its
-- two keys do, and which front end it opens.
--
-- Nothing here runs fzf or opens a window. The client is a stub, fzf-lua is a
-- fake module put in `package.loaded`, and `vim.ui.select` is a function that
-- records what it was offered, so a case is about the entries and the actions
-- rather than about somebody else's UI.

local picker = require("todoist.picker")

local MILK = {
  id = "6XGg",
  content = "Buy milk",
  priority = 3,
  labels = { "errands" },
  project_id = "220",
  section_id = "7",
  due = { date = "2026-09-18", string = "today" },
}

--- Every optional field as the JSON null the API can answer with. `vim.NIL` is
--- truthy, so this is the task that breaks a line built with `or {}`.
local BARE = {
  id = "6YHh",
  content = vim.NIL,
  priority = vim.NIL,
  labels = vim.NIL,
  project_id = vim.NIL,
  section_id = vim.NIL,
  due = vim.NIL,
}

local PROJECTS = { { id = "220", name = "Home" } }
local SECTIONS = { { id = "7", name = "Groceries", project_id = "220" } }

--- Run `steps` with the client, the list's view, both front ends and `notify`
--- stubbed.
---
--- `env` sets what the stubs answer: `tasks` is what the API returns, `shown`
--- is the view the list buffer is on (nil for no list open), `fzf` installs the
--- fake fzf-lua, and `picker_option` is the `picker` setting.
---@param env table
---@param steps fun(seen: table)
---@return table seen
local function drive(env, steps)
  local client = require("todoist.client")
  local list = require("todoist.list")
  local todoist = require("todoist")

  local seen = { reads = {}, notifications = {}, opened = {}, closed = {}, reopened = {}, select = nil, fzf = nil }

  local stubs = {
    get_tasks = function(callback)
      table.insert(seen.reads, { name = "all" })
      callback(env.tasks or { MILK })
    end,
    get_tasks_matching = function(filter, callback)
      table.insert(seen.reads, { name = "filtered", filter = filter })
      callback(env.tasks or { MILK })
    end,
    get_projects = function(callback)
      callback(PROJECTS)
    end,
    get_sections = function(callback)
      callback(SECTIONS)
    end,
    close_task = function(id, callback)
      table.insert(seen.closed, id)
      callback(nil, nil)
    end,
    reopen_task = function(id, callback)
      table.insert(seen.reopened, id)
      callback(nil, nil)
    end,
  }

  local reals = { notify = vim.notify, ui = vim.ui, options = todoist.options }
  for name in pairs(stubs) do
    reals[name] = client[name]
    client[name] = stubs[name]
  end

  local real_current_spec, real_refresh = list.current_spec, list.refresh
  list.current_spec = function()
    return env.shown
  end
  list.refresh = function() end

  local task_buffer = require("todoist.task_buffer")
  local real_open = task_buffer.open
  task_buffer.open = function(id)
    table.insert(seen.opened, id)
  end

  vim.notify = function(message)
    table.insert(seen.notifications, message)
  end
  vim.ui = {
    select = function(items, opts)
      seen.select = { items = items, opts = opts }
    end,
  }

  local real_fzf = package.loaded["fzf-lua"]
  package.loaded["fzf-lua"] = nil
  if env.fzf then
    package.loaded["fzf-lua"] = {
      fzf_exec = function(lines, opts)
        seen.fzf = { lines = lines, opts = opts }
      end,
    }
  end

  todoist.options = vim.tbl_extend("force", todoist.options, { picker = env.picker_option or "auto" })

  local ok, err = pcall(steps, seen)

  package.loaded["fzf-lua"] = real_fzf
  for name in pairs(stubs) do
    client[name] = reals[name]
  end
  list.current_spec, list.refresh = real_current_spec, real_refresh
  task_buffer.open = real_open
  vim.notify, vim.ui, todoist.options = reals.notify, reals.ui, reals.options

  assert(ok, err)

  return seen
end

--- The action bound to one fzf key, as the fake recorded it.
---@param seen table
---@param key string
---@return fun(selected: string[])
local function action(seen, key)
  assert(seen.fzf, "fzf-lua was not the front end")

  return seen.fzf.opts.actions[key]
end

return {
  ["a task becomes one line carrying content, due, priority, labels and its place"] = function()
    local entries = picker.entries({ MILK }, PROJECTS, SECTIONS)

    assert(#entries == 1, vim.inspect(entries))
    assert(entries[1].id == "6XGg", entries[1].id)
    assert(entries[1].text == "Buy milk  (2026-09-18)  p3  @errands  #Home/Groceries", entries[1].text)
  end,

  ["a task whose every optional field is null still becomes a line"] = function()
    local entries = picker.entries({ BARE }, PROJECTS, SECTIONS)

    assert(#entries == 1, vim.inspect(entries))
    assert(entries[1].id == "6YHh", entries[1].id)
    assert(entries[1].text == "", ("%q"):format(entries[1].text))
  end,

  ["a null in a project or section name is a line, not an error"] = function()
    local entries = picker.entries({ MILK }, { { id = "220", name = vim.NIL } }, { { id = "7", name = vim.NIL } })

    assert(entries[1].text == "Buy milk  (2026-09-18)  p3  @errands", entries[1].text)
  end,

  ["the search runs inside the filter of the view the list is showing"] = function()
    local seen = drive({ shown = { title = "today", filter = "today | overdue" }, fzf = true }, function()
      picker.pick()
    end)

    assert(#seen.reads == 1, vim.inspect(seen.reads))
    assert(seen.reads[1].name == "filtered", vim.inspect(seen.reads))
    assert(seen.reads[1].filter == "today | overdue", vim.inspect(seen.reads))
    assert(seen.fzf.opts.prompt == "Todoist: today  (today | overdue)> ", seen.fzf.opts.prompt)
  end,

  ["the unfiltered list searches every open task and says so"] = function()
    local seen = drive({ shown = { title = "all open tasks" }, fzf = true }, function()
      picker.pick()
    end)

    assert(seen.reads[1].name == "all", vim.inspect(seen.reads))
    assert(seen.fzf.opts.prompt == "Todoist: all open tasks> ", seen.fzf.opts.prompt)
  end,

  ["with no todoist buffer open it searches every open task"] = function()
    local seen = drive({ shown = nil, fzf = true }, function()
      picker.pick()
    end)

    assert(seen.reads[1].name == "all", vim.inspect(seen.reads))
    assert(seen.fzf.opts.prompt == "Todoist: all open tasks> ", seen.fzf.opts.prompt)
  end,

  ["a named view is searched whatever the list buffer is showing"] = function()
    local todoist = require("todoist")
    local views = todoist.options.views

    local seen = drive({ shown = { title = "all open tasks" }, fzf = true }, function()
      todoist.options.views = { work = "#Work" }
      picker.pick("work")
    end)

    todoist.options.views = views

    assert(seen.reads[1].filter == "#Work", vim.inspect(seen.reads))
  end,

  ["enter opens the task buffer of the task that was picked"] = function()
    local seen = drive({ tasks = { MILK, BARE }, fzf = true }, function(recorded)
      picker.pick()
      action(recorded, "enter")({ "6YHh\tsomething" })
    end)

    assert(vim.deep_equal(seen.opened, { "6YHh" }), vim.inspect(seen.opened))
  end,

  ["ctrl-x completes the task that was picked"] = function()
    local seen = drive({ tasks = { MILK, BARE }, fzf = true }, function(recorded)
      picker.pick()
      action(recorded, "ctrl-x")({ "6XGg\tBuy milk" })
    end)

    assert(vim.deep_equal(seen.closed, { "6XGg" }), vim.inspect(seen.closed))
    assert(#seen.opened == 0, vim.inspect(seen.opened))
  end,

  ["a complete made from the picker is what u reverses"] = function()
    local quick_edit = require("todoist.quick_edit")

    local seen = drive({}, function()
      quick_edit.forget()
      picker.complete_entry({ task = MILK })
      quick_edit.undo()
    end)

    assert(#seen.closed == 1, vim.inspect(seen.closed))
    assert(vim.deep_equal(seen.reopened, { "6XGg" }), vim.inspect(seen.reopened))
  end,

  ["fzf-lua is the front end when it loads"] = function()
    local seen = drive({ fzf = true }, function()
      picker.pick()
    end)

    assert(seen.fzf, "fzf-lua was not used")
    assert(seen.select == nil, "vim.ui.select was used as well")
    assert(seen.fzf.lines[1] == "6XGg\tBuy milk  (2026-09-18)  p3  @errands  #Home/Groceries", seen.fzf.lines[1])
    assert(seen.fzf.opts.fzf_opts["--with-nth"] == "2..", vim.inspect(seen.fzf.opts.fzf_opts))
  end,

  ["vim.ui.select is the front end when fzf-lua is absent"] = function()
    local seen = drive({ fzf = false }, function()
      picker.pick()
    end)

    assert(seen.fzf == nil, "fzf-lua was used")
    assert(seen.select, "vim.ui.select was not used")
    assert(seen.select.opts.prompt == "Todoist: all open tasks", seen.select.opts.prompt)
    assert(seen.select.opts.format_item(seen.select.items[1]):find("Buy milk", 1, true))
  end,

  ["the select option keeps vim.ui.select even with fzf-lua installed"] = function()
    local seen = drive({ fzf = true, picker_option = "select" }, function()
      picker.pick()
    end)

    assert(seen.fzf == nil, "fzf-lua was used")
    assert(seen.select, "vim.ui.select was not used")
  end,

  ["asking for fzf-lua without it installed falls back and says so"] = function()
    local seen = drive({ fzf = false, picker_option = "fzf-lua" }, function()
      picker.pick()
    end)

    assert(seen.select, "vim.ui.select was not used")
    assert(seen.notifications[1]:find("fzf-lua is not installed", 1, true), vim.inspect(seen.notifications))
  end,

  ["no open tasks says so instead of opening an empty picker"] = function()
    local seen = drive({ tasks = {}, fzf = true }, function()
      picker.pick()
    end)

    assert(seen.fzf == nil, "an empty picker was opened")
    assert(seen.select == nil, "an empty picker was opened")
    assert(#seen.notifications == 1, vim.inspect(seen.notifications))
    assert(seen.notifications[1]:find("no open tasks in Todoist: all open tasks", 1, true), seen.notifications[1])
  end,
}
