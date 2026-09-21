-- Fuzzy-search the objects of a view and act on the one you picked.
--
-- Two front ends over one list of entries: fzf-lua when it is installed, and
-- `vim.ui.select` otherwise. fzf-lua is an OPTIONAL dependency and is looked up
-- with `pcall(require, ...)` at the moment a picker is asked for, so a person
-- who does not have it installed never sees an error, and one who installs it
-- later gets it without restarting.
--
-- The search runs over the view the list buffer is showing, so a filtered view
-- searches inside its filter. The prompt carries the view's name and its query,
-- because a picker that quietly holds back objects reads as a bug.

local M = {}

local format = require("damnit.list_format")
local message = require("damnit.message")

--- What separates the oid from the text on an fzf line. fzf is told to display
--- and match from the second field on, so the oid travels with the entry
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

--- One object as one searchable line: what it is, when it is due, how urgent it
--- is, what it is labelled and where it sits.
---@param object table
---@return string
function M.line(object)
  local parts = { text(object.subject) }
  format.append_badges(parts, object)

  local path = text(object.path)
  if path ~= "" then
    parts[#parts + 1] = path
  end

  return table.concat(parts, "  ")
end

---@class damnit.PickerEntry
---@field oid string the object's oid, which the line never carries
---@field text string the line the operator searches and sees
---@field object table the object dam answered with

--- The entries a view's objects become, in the order dam gave them: dam has
--- already ordered them, and the front end ranks by the query anyway.
---@param objects table[]?
---@return damnit.PickerEntry[]
function M.entries(objects)
  local entries = {}

  for _, object in ipairs(objects or {}) do
    entries[#entries + 1] = { oid = text(object.oid), text = M.line(object), object = object }
  end

  return entries
end

--- Open the picked object as a task buffer.
---@param entry damnit.PickerEntry
function M.open_entry(entry)
  require("damnit.task_buffer").open(entry.oid)
end

--- Complete the picked object, through the same path the list's `x` takes, so a
--- parent dam refuses offers the same choice here.
---@param entry damnit.PickerEntry
function M.complete_entry(entry)
  require("damnit.done").send(entry.object, false)
end

--- The oid on an fzf selection, which is everything before the first delimiter.
---@param selected string[]? what fzf handed the action
---@return string
function M.chosen_oid(selected)
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
  local wanted = require("damnit").options.picker

  if wanted ~= "auto" and wanted ~= "fzf-lua" and wanted ~= "select" then
    message.warn(("picker %q is not auto, fzf-lua or select; using auto"):format(tostring(wanted)))
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
    message.warn("fzf-lua is not installed, so this is vim.ui.select")
  end

  return nil
end

---@param fzf_lua table
---@param entries damnit.PickerEntry[]
---@param title string
local function with_fzf_lua(fzf_lua, entries, title)
  local lines, by_oid = {}, {}

  for _, entry in ipairs(entries) do
    lines[#lines + 1] = entry.oid .. DELIMITER .. entry.text
    by_oid[entry.oid] = entry
  end

  local function act(handler)
    return function(selected)
      local entry = by_oid[M.chosen_oid(selected)]
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

---@param entries damnit.PickerEntry[]
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
---@param entries damnit.PickerEntry[]
---@param title string what the prompt says the search is inside
function M.show(entries, title)
  local fzf_lua = M.fzf_lua()

  if fzf_lua then
    return with_fzf_lua(fzf_lua, entries, title)
  end

  with_ui_select(entries, title)
end

--- Search one view's objects.
---
--- With no name the search follows the screen: the view the list buffer is
--- showing, or every open object when no list is up. A name searches that view
--- whatever is on screen, which is what a keymap bound to one view wants.
---@param name string? a view declared in `setup` or in dam's own config
function M.pick(name)
  local list = require("damnit.list")
  local views = require("damnit.views")
  local spec

  if name == nil or name == "" then
    spec = list.current_spec() or views.resolve(nil)
  else
    spec = views.resolve(name)
  end

  if not spec then
    return
  end

  local title = format.title(spec)

  list.fetch(spec, function(objects, err)
    if err then
      -- The queue has already raised dam's own message.
      return
    end

    local entries = M.entries(objects)
    if #entries == 0 then
      return message.warn(("no objects in %s"):format(title))
    end

    M.show(entries, title)
  end)
end

return M
