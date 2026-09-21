-- The text a list of objects looks like, and the object each line sits on.
--
-- Everything here is a pure function over tables: no buffer, no call, no
-- notification. `render` answers with the lines and, beside them, the object
-- each line was drawn from. That table is the only way a line maps back to an
-- object: nothing parses an oid out of display text, so the line may say
-- whatever reads best without a key mapping depending on its shape.
--
-- The layout is the tree, because in dam the tree is the path.

local M = {}

local location = require("damnit.location")
local tree = require("damnit.tree")

--- One level of nesting, in columns.
local INDENT = "  "

--- dam's least urgent priority, and its default, which is left off a line: a
--- badge on every object says nothing.
local LEAST_URGENT = 4

---@param value any
---@return string
local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

--- The labels an object carries. A JSON null decodes to `vim.NIL`, which is
--- truthy, so an absent list has to be recognised by its type rather than by
--- falling back with `or`.
---@param object table
---@return string[]
function M.labels_of(object)
  return type(object.labels) == "table" and object.labels or {}
end

--- The date dam resolved this object's due string to, which is what a list is
--- read for.
---@param object table
---@return string
function M.due_of(object)
  return text(type(object.task) == "table" and object.task.due or nil)
end

--- The badges every line carries after its subject: when it is due, how urgent
--- it is and what it is labelled, in that order. dam's scale runs 1 to 4 with 1
--- the most urgent, the reverse of Todoist's.
---
--- Shared by the list's own line and the picker's, so a null field or a badge's
--- wording is fixed once rather than in each rendering.
---@param parts string[] appended to in place
---@param object table
function M.append_badges(parts, object)
  local due = M.due_of(object)
  if due ~= "" then
    parts[#parts + 1] = "(" .. due .. ")"
  end

  local priority = tonumber(type(object.task) == "table" and object.task.priority or nil)
  if priority and priority < LEAST_URGENT then
    parts[#parts + 1] = "p" .. priority
  end

  for _, label in ipairs(M.labels_of(object)) do
    parts[#parts + 1] = "@" .. text(label)
  end
end

--- One object as one line: what it is, when it is due, how urgent it is, what
--- it is labelled and where it sits.
---
--- An object captured from code carries the location icon. It goes after the
--- subject, beside the other badges, so a narrow sidebar truncates a badge
--- rather than the subject: the columns the subject starts at do not move.
---
--- A folded object ends with how many objects are folded away under it, so a
--- tree that lost a level says where the level went.
---@param object table
---@param indent string
---@param folded integer? objects hidden under this line, when it is folded
---@return string
function M.object_line(object, indent, folded)
  local parts = { indent .. "- " .. text(object.subject) }
  M.append_badges(parts, object)

  if location.parse(object.body) then
    parts[#parts + 1] = location.ICON
  end

  local path = text(object.path)
  if path ~= "" then
    parts[#parts + 1] = path
  end

  if folded and folded > 0 then
    parts[#parts + 1] = ("(+%d)"):format(folded)
  end

  return table.concat(parts, "  ")
end

--- The heading that names the view, so a buffer says which list it is holding.
---@param spec damnit.ListSpec
---@return string
function M.title(spec)
  if spec.query then
    return ("dam: %s  (%s)"):format(spec.title, spec.query)
  end

  return "dam: " .. spec.title
end

--- What a view looks like when the call failed.
---
--- dam's own wording is the body of it, which is what keeps a query it rejected
--- from reading as a query that matched nothing.
---@param spec damnit.ListSpec
---@param err damnit.Error
---@return string[]
function M.refusal(spec, err)
  return { M.title(spec), "", "dam refused this view:", "", "  " .. err.message }
end

---@class damnit.ListEntry
---@field object table the object drawn on this line
---@field location damnit.Location? the location its body holds

--- A whole list as lines, plus the object each line holds.
---
--- An object with children heads a tree: its children follow it, one indent
--- further in per level, and an object whose parent this view does not hold
--- heads a tree of its own rather than disappearing.
---@param spec damnit.ListSpec
---@param objects table[] as dam returned them
---@param collapsed table<string, boolean>? paths whose children are folded away
---@return string[] lines
---@return table<integer, damnit.ListEntry> entry by line number
function M.render(spec, objects, collapsed)
  local folds = collapsed or {}
  local index = tree.index(objects or {})

  local lines = { M.title(spec), "" }
  local entries = {}
  local drawn = 0

  ---@param object table
  ---@param depth integer
  local function write(object, depth)
    local path = text(object.path)
    local hidden = folds[path] and tree.descendant_count(index, path) or 0

    lines[#lines + 1] = M.object_line(object, INDENT:rep(depth), hidden)
    entries[#lines] = { object = object, location = location.parse(object.body) }
    drawn = drawn + 1
  end

  for _, object in ipairs(objects or {}) do
    if tree.is_root(index, object) then
      tree.descend(index, object, folds, write)
    end
  end

  -- A view that matched nothing says so. It is a success with no objects, which
  -- is a different answer than a query dam refused.
  if drawn == 0 then
    lines[#lines + 1] = "No objects."
  end

  return lines, entries
end

return M
