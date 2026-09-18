-- The quick edits: one key each in the list, and where one needs words, one
-- prompt.
--
-- The keys are the herdr plugin's keys, so a hand that learned the pane knows
-- the list: `x`, `X`, `dd`, `p`, `s`, `l`, `m` and `a`, plus `u` for the undo
-- the pane does not have.
--
-- Every write is followed by a read of the view on screen, so what is drawn
-- comes from the server rather than from a guess at what the write did, and a
-- refused write leaves the lines where they are with the API's own message in a
-- notification the client already raised.
--
-- Nothing here is modal: a prompt is `vim.ui.input` and a picker is
-- `vim.ui.select`, so whatever the operator has configured those to be is what
-- they get.

local M = {}

local client = require("todoist.client")

--- The API's priority scale, where 4 is the app's p1 and 1 is no priority at
--- all. The vendor's own update parameter says "1 is highest" while its task
--- schema and the app say 4 is very urgent; the schema is what the API does.
local HIGHEST_PRIORITY = 4
local LOWEST_PRIORITY = 1

--- The one write `u` reverses: the last complete or reopen this session made.
---
--- One level and no stack. A second complete replaces it rather than stacking
--- on it, and nothing else a key does is recorded here, because completing is
--- the only quick edit with an exact opposite: a delete is gone, and a moved or
--- relabelled task has no remembered previous state to put back.
---@type { kind: "complete"|"reopen", id: string, content: string }?
local undoable = nil

---@param value any
---@return string
local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

---@param message string
---@param level integer?
local function say(message, level)
  vim.notify("todoist.nvim: " .. message, level or vim.log.levels.INFO)
end

--- Ask the API again for the view on screen.
local function reread()
  require("todoist.list").refresh()
end

--- The task the cursor is on, or nil after saying there is none.
---@return table?
local function under_cursor()
  return require("todoist.list").task_under_cursor()
end

--- What every write does with its answer: a refusal is the client's to report
--- and changes nothing on screen, and a success re-reads the view.
---@param done string what to say when the write worked
---@param remember { kind: "complete"|"reopen", id: string, content: string }?
---@return fun(data: any?, err: todoist.Error?)
local function wrote(done, remember)
  return function(_, err)
    if err then
      return
    end

    if remember then
      undoable = remember
    end
    reread()
    say(done)
  end
end

--- Complete one task, wherever it was picked. `u` puts it back.
---
--- The picker completes through here rather than through its own call, so one
--- complete is one code path and the undo remembers both of them.
---@param task table
function M.complete_task(task)
  local content = text(task.content)
  client.close_task(task.id, wrote("completed " .. content, { kind = "complete", id = task.id, content = content }))
end

--- Complete the task under the cursor. `u` puts it back.
function M.complete()
  local task = under_cursor()
  if not task then
    return
  end

  M.complete_task(task)
end

--- Reopen the task under the cursor, for a list whose filter shows completed
--- tasks. `u` completes it again.
function M.reopen()
  local task = under_cursor()
  if not task then
    return
  end

  local content = text(task.content)
  client.reopen_task(task.id, wrote("reopened " .. content, { kind = "reopen", id = task.id, content = content }))
end

--- Delete the task under the cursor, after a yes or no.
---
--- The pane asks with a second `d`; here `dd` is already the one mapping, so the
--- confirm is its own question. Todoist keeps no undo for a delete and neither
--- does this, which is why the question is asked at all.
function M.delete()
  local task = under_cursor()
  if not task then
    return
  end

  local content = text(task.content)
  if vim.fn.confirm(("Delete %q?"):format(content), "&Yes\n&No", 2) ~= 1 then
    return say("left that task alone")
  end

  client.delete_task(task.id, wrote("deleted " .. content))
end

--- One step up in urgency, wrapping from the most urgent back to none.
---@param priority any
---@return integer
function M.cycled(priority)
  local current = tonumber(priority) or LOWEST_PRIORITY

  if current >= HIGHEST_PRIORITY or current < LOWEST_PRIORITY then
    return LOWEST_PRIORITY
  end

  return current + 1
end

--- Cycle the priority of the task under the cursor.
function M.cycle_priority()
  local task = under_cursor()
  if not task then
    return
  end

  local next_priority = M.cycled(task.priority)
  client.update_task(task.id, { priority = next_priority }, wrote("priority p" .. next_priority))
end

--- Set the due date of the task under the cursor from a line of Todoist's own
--- natural language, which the API parses: an unreadable one comes back in its
--- words rather than being guessed at here.
function M.schedule()
  local task = under_cursor()
  if not task then
    return
  end

  vim.ui.input({ prompt = "Due: " }, function(due)
    if not due or vim.trim(due) == "" then
      return
    end

    client.update_task(task.id, { due_string = due }, wrote("due " .. due))
  end)
end

--- Every label the picker offers: the account's labels, then any label the task
--- carries that the account no longer lists, so a stray one can still be taken
--- off.
---
--- A label the API answered without a name is left out: a label is written back
--- by name, so a nameless one is nothing this can toggle. Ordering reads both
--- fields through a fallback, so a null order or a null name sorts rather than
--- raising.
---@param on string[] the labels the task carries
---@param known table[] the account's labels
---@return { name: string, on: boolean }[]
function M.label_choices(on, known)
  local choices, seen = {}, {}

  for _, label in ipairs(known or {}) do
    local name = text(label.name)
    if name ~= "" and not seen[name] then
      seen[name] = true
      choices[#choices + 1] =
        { name = name, on = vim.tbl_contains(on, name), order = tonumber(label.order) or math.huge }
    end
  end

  table.sort(choices, function(left, right)
    if left.order ~= right.order then
      return left.order < right.order
    end

    return left.name < right.name
  end)

  for _, name in ipairs(on) do
    if not seen[name] then
      choices[#choices + 1] = { name = name, on = true }
    end
  end

  return choices
end

--- The label set a toggle writes: every label still marked, with the chosen one
--- flipped.
---@param choices { name: string, on: boolean }[]
---@param at integer
---@return string[]
function M.toggled(choices, at)
  local labels = {}

  for index, choice in ipairs(choices) do
    if choice.on ~= (index == at) then
      labels[#labels + 1] = choice.name
    end
  end

  return labels
end

--- Toggle one label on the task under the cursor, from a picker of the
--- account's labels.
function M.labels()
  local task = under_cursor()
  if not task then
    return
  end

  client.get_labels(function(known, err)
    if err then
      return
    end

    local on = type(task.labels) == "table" and task.labels or {}
    local choices = M.label_choices(on, known)
    if #choices == 0 then
      return say("no labels")
    end

    vim.ui.select(choices, {
      prompt = "Labels",
      format_item = function(choice)
        return ("[%s] %s"):format(choice.on and "x" or " ", choice.name)
      end,
    }, function(choice, index)
      if not choice then
        return
      end

      local labels = M.toggled(choices, index)
      local done = ("@%s %s"):format(choice.name, choice.on and "off" or "on")
      client.update_task(task.id, { labels = labels }, wrote(done))
    end)
  end)
end

--- Every project, each followed by its own sections, in the order the API gave
--- them: Todoist already sorts both the way the app shows them.
---@param projects table[]
---@param sections table[]
---@return { label: string, to: table }[]
function M.destinations(projects, sections)
  local entries = {}

  for _, project in ipairs(projects or {}) do
    local id = text(project.id)
    entries[#entries + 1] = { label = text(project.name), to = { project_id = id } }

    for _, section in ipairs(sections or {}) do
      if text(section.project_id) == id then
        entries[#entries + 1] = { label = "  " .. text(section.name), to = { section_id = text(section.id) } }
      end
    end
  end

  return entries
end

--- Move the task under the cursor to a project or a section.
function M.move()
  local task = under_cursor()
  if not task then
    return
  end

  client.get_projects(function(projects, err)
    if err then
      return
    end

    client.get_sections(function(sections, failure)
      if failure then
        return
      end

      local entries = M.destinations(projects, sections)
      if #entries == 0 then
        return say("no projects")
      end

      vim.ui.select(entries, {
        prompt = "Move to",
        format_item = function(entry)
          return entry.label
        end,
      }, function(entry)
        if not entry then
          return
        end

        client.move_task(task.id, entry.to, wrote("moved to " .. vim.trim(entry.label)))
      end)
    end)
  end)
end

--- Add a task from a whole line of Quick Add syntax, which Todoist parses.
function M.add()
  vim.ui.input({ prompt = "Quick add: " }, function(line)
    if not line or vim.trim(line) == "" then
      return
    end

    client.quick_add(line, function(task, err)
      if err then
        return
      end

      reread()
      say("added " .. text(task and task.content or line))
    end)
  end)
end

--- Reverse the last complete or reopen of this session.
---
--- One level deep: the reversal itself is not undoable, and a key that is
--- neither `x` nor `X` leaves the remembered write alone rather than clearing
--- it. A refused reversal keeps the write remembered, so it can be tried again,
--- and re-reads the view so what is on screen is what the server holds.
function M.undo()
  local last = undoable
  if not last then
    return say("nothing to undo", vim.log.levels.WARN)
  end

  local reverse = last.kind == "complete" and client.reopen_task or client.close_task
  local done = last.kind == "complete" and "reopened " or "completed again "

  reverse(last.id, function(_, err)
    if err then
      return reread()
    end

    undoable = nil
    reread()
    say(done .. last.content)
  end)
end

--- Forget the remembered write, so `u` has nothing to reverse. The undo is the
--- session's, not the view's, so nothing here calls this: a spec does, to start
--- from nothing.
function M.forget()
  undoable = nil
end

--- Bind the quick edits to a list buffer.
---@param buf integer
function M.attach(buf)
  local keys = {
    x = { M.complete, "complete this task" },
    X = { M.reopen, "reopen this task" },
    dd = { M.delete, "delete this task, after the confirm" },
    p = { M.cycle_priority, "cycle this task's priority" },
    s = { M.schedule, "set this task's due date" },
    l = { M.labels, "toggle a label on this task" },
    m = { M.move, "move this task to a project or section" },
    a = { M.add, "add a task from a Quick Add line" },
    u = { M.undo, "undo the last complete or reopen" },
  }

  for key, bound in pairs(keys) do
    vim.keymap.set("n", key, bound[1], { buffer = buf, desc = "Todoist: " .. bound[2] })
  end
end

return M
