-- The text a list of tasks looks like, and the line each task sits on.
--
-- Everything here is a pure function over tables: no buffer, no request, no
-- notification. `render` answers with the lines and, beside them, a table from
-- line number to task id. That table is the only way a line maps back to a
-- task: nothing parses an id out of display text, so the line may say whatever
-- reads best without a key mapping depending on its shape.
--
-- Grouping follows the order the API gave. Todoist already sorts projects and
-- sections the way the app shows them, so keeping that order means both
-- plugins and the app agree on what comes first.

local M = {}

local location = require("todoist.location")
local tree = require("todoist.tree")

--- The indent each kind of line carries. Two spaces per level, so a task under
--- a section is four in and a task directly under a project is two.
local PROJECT_INDENT = ""
local SECTION_INDENT = "  "

--- Tasks with no section come before the sections do, which is where the app
--- puts them. The empty string is the bucket key for that group.
local NO_SECTION = ""

---@param value any
---@return string
local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

--- The name to head a group with, falling back to the id when the API listed a
--- task under something it did not list itself: an id says less than a name but
--- more than dropping the task.
---@param names table<string, string>
---@param id string
---@return string
local function heading(names, id)
  if id == "" then
    return "(no project)"
  end

  local name = names[id]
  if name == nil or name == "" then
    return id
  end

  return name
end

---@param items table[]?
---@return table<string, string> name keyed by id
---@return string[] ids in the order the API gave them
local function names_by_id(items)
  local names, order = {}, {}

  for _, item in ipairs(items or {}) do
    local id = text(item.id)
    if id ~= "" and names[id] == nil then
      names[id] = text(item.name)
      order[#order + 1] = id
    end
  end

  return names, order
end

--- The due date Todoist recorded, preferring the calendar date it resolved to
--- over the string it was typed as: a list is read for when things are due.
---@param task table
---@return string
local function due_of(task)
  local due = task.due
  if type(due) ~= "table" then
    return ""
  end

  local value = text(due.date)
  if value == "" then
    value = text(due.string)
  end

  return value
end

--- One task as one line: what it is, when it is due, how urgent it is and what
--- it is labelled. A task carries a bullet and a heading does not, which is
--- what separates a section's name from a task sitting at the same indent. `p4` is the API's own priority scale, the same one the task
--- buffer shows, where 4 is the most urgent. Priority 1 is no priority and is
--- left off rather than written out.
---
--- A task captured from code ends with the location icon. It goes last, beside
--- the other badges, so a narrow sidebar truncates the icon rather than the
--- content: the columns the content starts at do not move.
---
--- A folded task ends with how many children are folded away under it, so a
--- tree that lost a level says where the level went.
---@param task table
---@param indent string
---@param where todoist.Location? the location its description holds
---@param folded integer? children hidden under this line, when it is folded
---@return string
function M.task_line(task, indent, where, folded)
  local parts = { indent .. "  - " .. text(task.content) }

  local due = due_of(task)
  if due ~= "" then
    parts[#parts + 1] = "(" .. due .. ")"
  end

  local priority = tonumber(task.priority) or 1
  if priority > 1 then
    parts[#parts + 1] = "p" .. priority
  end

  for _, label in ipairs(task.labels or {}) do
    parts[#parts + 1] = "@" .. text(label)
  end

  if where then
    parts[#parts + 1] = location.ICON
  end

  if folded and folded > 0 then
    parts[#parts + 1] = ("(+%d)"):format(folded)
  end

  return table.concat(parts, "  ")
end

--- The heading that names the view, so a buffer says which list it is holding.
---@param spec todoist.ListSpec
---@return string
function M.title(spec)
  if spec.filter then
    return ("Todoist: %s  (%s)"):format(spec.title, spec.filter)
  end

  return "Todoist: " .. spec.title
end

--- What a view looks like when the request failed.
---
--- The API's own wording is the body of it, which is what keeps a filter it
--- rejected from reading as a filter that matched nothing.
---@param spec todoist.ListSpec
---@param err todoist.Error
---@return string[]
function M.refusal(spec, err)
  return { M.title(spec), "", "The API refused this view:", "", "  " .. err.message }
end

--- Bucket tasks by project and then by section, keeping the API's order and
--- giving a task whose project the API did not list a group of its own.
---@param tasks table[]
---@param project_order string[] project ids in the API's order
---@return table<string, table<string, table[]>> buckets
---@return string[] project_ids in render order
local function bucket(tasks, project_order)
  local buckets, project_ids = {}, {}

  local function project_bucket(project_id)
    if not buckets[project_id] then
      buckets[project_id] = {}
      project_ids[#project_ids + 1] = project_id
    end

    return buckets[project_id]
  end

  -- Seeded in the API's order first, so a project the API did not list lands
  -- after the ones it did.
  for _, project_id in ipairs(project_order) do
    project_bucket(project_id)
  end

  for _, task in ipairs(tasks) do
    local sections = project_bucket(text(task.project_id))
    local section_id = text(task.section_id)

    sections[section_id] = sections[section_id] or {}
    table.insert(sections[section_id], task)
  end

  return buckets, project_ids
end

---@param sections table[]?
---@return table<string, string[]> section ids per project, in the API's order
local function sections_by_project(sections)
  local by_project = {}

  for _, section in ipairs(sections or {}) do
    local project_id = text(section.project_id)
    by_project[project_id] = by_project[project_id] or {}
    table.insert(by_project[project_id], text(section.id))
  end

  return by_project
end

--- Order one project's section buckets: the API's order first, then any section
--- the API did not list, so no task is dropped for want of a heading.
---@param present table<string, table[]>
---@param ordered string[]
---@return string[]
local function section_render_order(present, ordered)
  local render, seen = {}, {}

  for _, section_id in ipairs(ordered) do
    if present[section_id] then
      render[#render + 1] = section_id
      seen[section_id] = true
    end
  end

  local leftover = {}
  for section_id in pairs(present) do
    if section_id ~= NO_SECTION and not seen[section_id] then
      leftover[#leftover + 1] = section_id
    end
  end
  table.sort(leftover)

  return vim.list_extend(render, leftover)
end

---@class todoist.ListSpec
---@field title string the name the buffer reports, a view's name or a phrase
---@field filter string? a Todoist filter query, or nil for every open task

--- A whole list as lines, plus the task each line holds.
---
--- A task with children is drawn as the head of a tree: its subtasks follow it,
--- two spaces further in per level, wherever their own project and section
--- would have put them. Only the head of a tree is grouped, so a subtask never
--- appears twice, and a task whose parent this view does not hold heads a tree
--- of its own rather than disappearing.
---@param spec todoist.ListSpec
---@param tasks table[] as the API returned them
---@param projects table[] every project, for the headings
---@param sections table[] every section, for the headings
---@param collapsed table<string, boolean>? task ids whose subtasks are folded away
---@return string[] lines
---@return table<integer, string> task id by line number
---@return table<integer, todoist.Location> location by line number, where one was captured
function M.render(spec, tasks, projects, sections, collapsed)
  local project_names, project_order = names_by_id(projects)
  local section_names = names_by_id(sections)
  local section_order = sections_by_project(sections)

  local folds = collapsed or {}
  local forest = tree.index(tasks or {})

  local roots = {}
  for _, task in ipairs(tasks or {}) do
    if tree.is_root(forest, task) then
      roots[#roots + 1] = task
    end
  end

  local buckets, project_ids = bucket(roots, project_order)

  local lines = { M.title(spec), "" }
  local ids, locations = {}, {}

  local function write(line, task, where)
    lines[#lines + 1] = line
    if task then
      ids[#lines] = text(task.id)
      locations[#lines] = where
    end
  end

  local rendered = 0

  --- A task's own line and the location it holds, parsed once for both the icon
  --- and the jump.
  ---@param task table
  ---@param indent string
  local function write_task(task, indent)
    local where = location.parse(task.description)
    local id = text(task.id)
    local hidden = folds[id] and tree.child_count(forest, id) or 0

    write(M.task_line(task, indent, where, hidden), task, where)
    rendered = rendered + 1
  end

  --- A task and everything under it, one level of indent per level of the tree.
  ---@param task table
  ---@param indent string
  local function write_subtree(task, indent)
    tree.descend(forest, task, folds, function(node, depth)
      write_task(node, indent .. SECTION_INDENT:rep(depth))
    end)
  end

  for _, project_id in ipairs(project_ids) do
    local present = buckets[project_id]
    local order = section_render_order(present, section_order[project_id] or {})

    local project_tasks = present[NO_SECTION] or {}
    if #project_tasks > 0 or #order > 0 then
      write(PROJECT_INDENT .. heading(project_names, project_id))

      for _, task in ipairs(project_tasks) do
        write_subtree(task, PROJECT_INDENT)
      end

      for _, section_id in ipairs(order) do
        write(SECTION_INDENT .. heading(section_names, section_id))
        for _, task in ipairs(present[section_id]) do
          write_subtree(task, SECTION_INDENT)
        end
      end

      write("")
    end
  end

  -- A view that matched nothing says so. It is a success with no tasks, which
  -- is a different answer than a filter the API refused.
  if rendered == 0 then
    write("No tasks.")
  end

  return lines, ids, locations
end

return M
