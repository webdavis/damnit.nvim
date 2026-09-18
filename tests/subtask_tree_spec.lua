-- The tree in the buffer: what `za` folds, what `>` and `<` send, and what
-- completing a parent asks first.
--
-- The client is a stub here, so no curl runs and no port is opened: a view is
-- drawn from tasks made up in the case, and every write is recorded rather than
-- sent. The rendering itself is pinned in list_format_spec and the wire in the
-- loopback specs.

local client = require("todoist.client")
local list = require("todoist.list")
local quick_edit = require("todoist.quick_edit")

local PROJECTS = { { id = "1", name = "Errands" } }

--- A parent, its two children and a grandchild under the first of them. Every
--- top-level task carries `parent_id` as `vim.NIL`, which is what the API's
--- JSON null decodes to.
local TASKS = {
  { id = "p", content = "Ship the release", project_id = "1", parent_id = vim.NIL },
  { id = "c1", content = "Tag it", project_id = "1", parent_id = "p" },
  { id = "g", content = "Sign the tag", project_id = "1", parent_id = "c1" },
  { id = "c2", content = "Write the notes", project_id = "1", parent_id = "p" },
  { id = "t", content = "Buy milk", project_id = "1", parent_id = vim.NIL },
}

--- Draw one view from `tasks` and run `steps` over the buffer it drew.
---
--- `confirm` is what the yes or no question is answered with, 1 being yes.
---@param env { tasks: table[]?, confirm: integer? }
---@param steps fun(seen: table)
---@return table seen
local function with_view(env, steps)
  local tasks = env.tasks or TASKS
  local seen = { calls = {}, notifications = {}, asked = {} }

  local stubs = {
    get_tasks = function(callback)
      callback(vim.deepcopy(tasks))
    end,
    get_projects = function(callback)
      callback(PROJECTS)
    end,
    get_sections = function(callback)
      callback({})
    end,
    move_task = function(id, destination, callback)
      table.insert(seen.calls, { name = "move", id = id, body = destination })
      callback(nil, nil)
    end,
    close_task = function(id, callback)
      table.insert(seen.calls, { name = "close", id = id })
      callback(nil, nil)
    end,
  }

  local reals = { notify = vim.notify, confirm = vim.fn.confirm }
  for name in pairs(stubs) do
    reals[name] = client[name]
    client[name] = stubs[name]
  end

  vim.notify = function(message)
    table.insert(seen.notifications, message)
  end
  vim.fn.confirm = function(question)
    table.insert(seen.asked, question)
    return env.confirm or 1
  end

  list.forget_folds()
  quick_edit.forget()
  list.open({ title = "all open tasks" })
  seen.buf = vim.api.nvim_get_current_buf()

  local ok, err = pcall(steps, seen)

  for name in pairs(stubs) do
    client[name] = reals[name]
  end
  vim.notify, vim.fn.confirm = reals.notify, reals.confirm

  assert(ok, err)

  return seen
end

---@param seen table
---@return string[]
local function lines(seen)
  return vim.api.nvim_buf_get_lines(seen.buf, 0, -1, false)
end

---@param seen table
---@param needle string
---@return integer
local function line_of(seen, needle)
  for number, line in ipairs(lines(seen)) do
    if line:find(needle, 1, true) then
      return number
    end
  end

  error(needle .. " is on no line: " .. table.concat(lines(seen), "\n"))
end

---@param seen table
---@param needle string
local function cursor_on(seen, needle)
  vim.api.nvim_win_set_cursor(0, { line_of(seen, needle), 0 })
end

---@param seen table
---@param needle string
---@return boolean
local function drawn(seen, needle)
  return table.concat(lines(seen), "\n"):find(needle, 1, true) ~= nil
end

return {
  ["za folds a task's subtasks away, and a second za brings them back"] = function()
    with_view({}, function(seen)
      cursor_on(seen, "Ship the release")
      list.toggle_fold()

      assert(not drawn(seen, "Tag it"), table.concat(lines(seen), "\n"))
      assert(not drawn(seen, "Sign the tag"), "a fold takes the whole subtree, not one level")
      assert(drawn(seen, "Ship the release  (+2)"), table.concat(lines(seen), "\n"))
      assert(drawn(seen, "Buy milk"), "folding one task hid another")

      list.toggle_fold()
      assert(drawn(seen, "Tag it"), table.concat(lines(seen), "\n"))
      assert(drawn(seen, "Sign the tag"), table.concat(lines(seen), "\n"))
    end)
  end,

  ["za on a task with no subtasks says so and changes nothing"] = function()
    with_view({}, function(seen)
      cursor_on(seen, "Buy milk")
      local before = table.concat(lines(seen), "\n")

      list.toggle_fold()

      assert(table.concat(lines(seen), "\n") == before, table.concat(lines(seen), "\n"))
      assert(seen.notifications[1]:find("no subtasks here", 1, true), vim.inspect(seen.notifications))
    end)
  end,

  ["a folded task stays folded when the view is re-read"] = function()
    with_view({}, function(seen)
      cursor_on(seen, "Ship the release")
      list.toggle_fold()

      list.refresh()

      assert(drawn(seen, "Ship the release  (+2)"), table.concat(lines(seen), "\n"))
      assert(not drawn(seen, "Tag it"), "the refresh unfolded the tree")
    end)
  end,

  ["> makes the task a subtask of the top-level task above it"] = function()
    local seen = with_view({}, function(view)
      cursor_on(view, "Buy milk")
      list.indent()
    end)

    assert(#seen.calls == 1, vim.inspect(seen.calls))
    assert(seen.calls[1].id == "t", vim.inspect(seen.calls))
    assert(vim.deep_equal(seen.calls[1].body, { parent_id = "c2" }), vim.inspect(seen.calls))
  end,

  ["> under a sibling at the same level sends it under that sibling"] = function()
    local seen = with_view({}, function(view)
      cursor_on(view, "Write the notes")
      list.indent()
    end)

    -- The row above "Write the notes" is the grandchild, which is what the app
    -- indents under too: the task on the row above, at whatever depth.
    assert(vim.deep_equal(seen.calls[1].body, { parent_id = "g" }), vim.inspect(seen.calls))
  end,

  ["> on a task already under the task above it sends nothing"] = function()
    local seen = with_view({}, function(view)
      cursor_on(view, "Tag it")
      list.indent()
    end)

    assert(#seen.calls == 0, vim.inspect(seen.calls))
    assert(seen.notifications[1]:find("already under Ship the release", 1, true), vim.inspect(seen.notifications))
  end,

  ["> on the first task in the view sends nothing and says why"] = function()
    local seen = with_view({}, function(view)
      cursor_on(view, "Ship the release")
      list.indent()
    end)

    assert(#seen.calls == 0, vim.inspect(seen.calls))
    assert(seen.notifications[1]:find("nothing above", 1, true), vim.inspect(seen.notifications))
  end,

  ["< moves a subtask out from under its parent"] = function()
    local seen = with_view({}, function(view)
      cursor_on(view, "Sign the tag")
      list.promote()
    end)

    assert(seen.calls[1].id == "g", vim.inspect(seen.calls))
    assert(vim.deep_equal(seen.calls[1].body, { parent_id = "p" }), vim.inspect(seen.calls))
  end,

  ["< on a top-level task sends nothing and says why"] = function()
    local seen = with_view({}, function(view)
      cursor_on(view, "Buy milk")
      list.promote()
    end)

    assert(#seen.calls == 0, vim.inspect(seen.calls))
    assert(seen.notifications[1]:find("already at the top level", 1, true), vim.inspect(seen.notifications))
  end,

  ["a key on an indented row acts on that row's own task"] = function()
    local seen = with_view({}, function(view)
      cursor_on(view, "Sign the tag")

      local task = list.task_under_cursor()
      assert(task and task.id == "g", vim.inspect(task))

      local opened = nil
      local task_buffer = require("todoist.task_buffer")
      local real_open = task_buffer.open
      task_buffer.open = function(id)
        opened = id
      end

      list.open_task_under_cursor()

      task_buffer.open = real_open
      assert(opened == "g", vim.inspect(opened))

      quick_edit.complete()
    end)

    assert(seen.calls[1].name == "close" and seen.calls[1].id == "g", vim.inspect(seen.calls))
  end,
}
