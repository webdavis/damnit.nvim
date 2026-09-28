local M = {}

local location = require("damnit.location")
local tree = require("damnit.tree")

local INDENT_PER_LEVEL = "  "

local DEFAULT_LEAST_URGENT_PRIORITY = 4

local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

function M.labels_of(object)
  return type(object.labels) == "table" and object.labels or {}
end

function M.due_of(object)
  return text(type(object.task) == "table" and object.task.due or nil)
end

function M.append_badges(parts, object)
  local due = M.due_of(object)
  if due ~= "" then
    parts[#parts + 1] = "(" .. due .. ")"
  end

  local priority = tonumber(type(object.task) == "table" and object.task.priority or nil)
  if priority and priority < DEFAULT_LEAST_URGENT_PRIORITY then
    parts[#parts + 1] = "p" .. priority
  end

  for _, label in ipairs(M.labels_of(object)) do
    parts[#parts + 1] = "@" .. text(label)
  end
end

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

function M.title(spec)
  if spec.query then
    return ("dam: %s  (%s)"):format(spec.title, spec.query)
  end

  return "dam: " .. spec.title
end

function M.refusal(spec, err)
  return { M.title(spec), "", "dam refused this view:", "", "  " .. err.message }
end

local function completed_at_of(object)
  return text(type(object.task) == "table" and object.task.completed_at or nil)
end

function M.by_completion(objects)
  local seats = {}
  for index, object in ipairs(objects) do
    seats[index] = { object = object, at = completed_at_of(object), index = index }
  end

  table.sort(seats, function(left, right)
    if left.at ~= right.at then
      return left.at > right.at
    end

    return left.index < right.index
  end)

  local ordered = {}
  for index, seat in ipairs(seats) do
    ordered[index] = seat.object
  end

  return ordered
end

function M.render(spec, objects, collapsed)
  local folds = collapsed or {}
  local index = tree.index(objects or {})

  local lines = { M.title(spec), "" }
  local entries = {}
  local drawn = 0

  local function write(object, depth)
    local path = text(object.path)
    local hidden = folds[path] and tree.descendant_count(index, path) or 0

    lines[#lines + 1] = M.object_line(object, INDENT_PER_LEVEL:rep(depth), hidden)
    entries[#lines] = { object = object, location = location.parse(object.body) }
    drawn = drawn + 1
  end

  if spec.flat then
    for _, object in ipairs(M.by_completion(objects or {})) do
      write(object, 0)
    end
  else
    for _, object in ipairs(objects or {}) do
      if tree.is_root(index, object) then
        tree.descend(index, object, folds, write)
      end
    end
  end

  local matched_nothing = drawn == 0
  if matched_nothing then
    lines[#lines + 1] = "No objects."
  end

  return lines, entries
end

return M
