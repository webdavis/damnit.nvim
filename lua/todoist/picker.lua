-- Fuzzy-search the open tasks and act on the one you picked.
--
-- Two front ends over one list of entries: fzf-lua when it is installed, and
-- `vim.ui.select` otherwise. fzf-lua is an OPTIONAL dependency and is looked up
-- with `pcall(require, ...)` at the moment a picker is asked for, so a person
-- who does not have it installed never sees an error, and one who installs it
-- later gets it without restarting.
--
-- The search runs over the view the list buffer is showing, so a filtered view
-- searches inside its filter. The prompt carries the view's name and its filter
-- query, because a picker that quietly holds back tasks reads as a bug.
--
-- Every field a line is built from can come back as a JSON null, which decodes
-- to `vim.NIL` and is truthy, so each one goes through the same `text` and
-- `type(...) == "table"` guards the rest of the plugin uses.

local M = {}

local format = require("todoist.list_format")
local tree = require("todoist.tree")

--- What separates the task id from the text on an fzf line. fzf is told to
--- display and match from the second field on, so the id travels with the entry
--- without being searched or shown, and nothing is parsed back out of what the
--- operator sees.
local DELIMITER = "\t"

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

--- One task as one searchable line: what it is, when it is due, how urgent it
--- is, what it is labelled and where it lives.
---@param task table
---@param projects table<string, string> project names by id
---@param sections table<string, string> section names by id
---@return string
function M.line(task, projects, sections)
  local parts = { text(task.content) }
  format.append_badges(parts, task)

  local place = projects[text(task.project_id)] or ""
  local section = sections[text(task.section_id)] or ""
  if section ~= "" then
    place = place ~= "" and (place .. "/" .. section) or section
  end

  if place ~= "" then
    parts[#parts + 1] = "#" .. place
  end

  return table.concat(parts, "  ")
end

--- The entries a set of tasks becomes, in the order the API gave them: Todoist
--- has already ordered them, and fzf ranks by the query anyway.
---
--- Each entry carries how many open subtasks it has among these same tasks,
--- because completing a parent closes them server side and the picker has no
--- buffer to count a tree in.
---@param tasks table[]?
---@param projects table[]?
---@param sections table[]?
---@return { id: string, text: string, task: table, open_subtasks: integer }[]
function M.entries(tasks, projects, sections)
  local project_names = format.names_by_id(projects)
  local section_names = format.names_by_id(sections)
  local forest = tree.index(tasks or {})

  local entries = {}
  for _, task in ipairs(tasks or {}) do
    local id = text(task.id)
    entries[#entries + 1] = {
      id = id,
      text = M.line(task, project_names, section_names),
      task = task,
      open_subtasks = tree.child_count(forest, id),
    }
  end

  return entries
end

--- Open the picked task in task 115's buffer.
---@param entry { id: string }
function M.open_entry(entry)
  require("todoist.task_buffer").open(entry.id)
end

--- Complete the picked task, through the same path the list's `x` takes, so a
--- parent asks before its subtasks go with it and `u` reverses a complete made
--- here as well.
---@param entry { task: table, open_subtasks: integer? }
function M.complete_entry(entry)
  require("todoist.quick_edit").complete_asking(entry.task, entry.open_subtasks or 0)
end

--- The id on an fzf selection, which is everything before the first delimiter.
---@param selected string[]? what fzf handed the action
---@return string
function M.chosen_id(selected)
  local line = type(selected) == "table" and selected[1] or nil

  return type(line) == "string" and (line:match("^([^" .. DELIMITER .. "]*)") or "") or ""
end

--- fzf-lua, when it is installed and the options allow it.
---
--- `auto` takes it when it loads. `select` never does. `fzf-lua` asks for it and
--- says so when it is absent rather than failing, because a picker that refuses
--- to open is worse than one that opens in the other front end.
---@return table? fzf_lua
function M.fzf_lua()
  local wanted = require("todoist").options.picker

  if wanted ~= "auto" and wanted ~= "fzf-lua" and wanted ~= "select" then
    say(("picker %q is not auto, fzf-lua or select; using auto"):format(wanted), vim.log.levels.WARN)
    wanted = "auto"
  end

  if wanted == "select" then
    return nil
  end

  local ok, module = pcall(require, "fzf-lua")
  if ok then
    return module
  end

  if wanted == "fzf-lua" then
    say("fzf-lua is not installed, so this is vim.ui.select", vim.log.levels.WARN)
  end

  return nil
end

---@param entries { id: string, text: string, task: table, open_subtasks: integer }[]
---@param title string
local function with_fzf_lua(fzf_lua, entries, title)
  local lines, by_id = {}, {}

  for _, entry in ipairs(entries) do
    lines[#lines + 1] = entry.id .. DELIMITER .. entry.text
    by_id[entry.id] = entry
  end

  local function act(handler)
    return function(selected)
      local entry = by_id[M.chosen_id(selected)]
      if entry then
        handler(entry)
      end
    end
  end

  fzf_lua.fzf_exec(lines, {
    prompt = title .. "> ",
    fzf_opts = { ["--delimiter"] = DELIMITER, ["--with-nth"] = "2.." },
    actions = { ["enter"] = act(M.open_entry), ["ctrl-x"] = act(M.complete_entry) },
  })
end

---@param entries { id: string, text: string, task: table, open_subtasks: integer }[]
---@param title string
local function with_ui_select(entries, title)
  vim.ui.select(entries, {
    prompt = title,
    format_item = function(entry)
      return entry.text
    end,
  }, function(entry)
    if entry then
      M.open_entry(entry)
    end
  end)
end

--- Put the entries in front of the operator in whichever front end is available.
---@param entries { id: string, text: string, task: table, open_subtasks: integer }[]
---@param title string what the prompt says the search is inside
function M.show(entries, title)
  local fzf_lua = M.fzf_lua()

  if fzf_lua then
    return with_fzf_lua(fzf_lua, entries, title)
  end

  with_ui_select(entries, title)
end

--- Search the open tasks of a view.
---
--- With no name the search follows the screen: the view the list buffer is
--- showing, or every open task when no list is open. A name searches that view
--- whatever is on screen, which is what a keymap bound to one view wants.
---@param name string? a view declared in `setup`, or nil to follow the screen
function M.pick(name)
  local list = require("todoist.list")
  local spec

  if name == nil or name == "" then
    spec = list.current_spec() or require("todoist").view(nil)
  else
    spec = require("todoist").view(name)
  end

  if not spec then
    return
  end

  local title = format.title(spec)

  list.fetch(spec.filter, function(data, err)
    if err then
      -- The client has already raised the API's own message.
      return
    end

    local entries = M.entries(data.tasks, data.projects, data.sections)
    if #entries == 0 then
      return say(("no open tasks in %s"):format(title), vim.log.levels.WARN)
    end

    M.show(entries, title)
  end)
end

return M
