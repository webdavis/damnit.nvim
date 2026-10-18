local M = {}

local dam_object = require("damnit.object")
local text = dam_object.text
local location = require("damnit.location")
local tree = require("damnit.tree")

local INDENT_PER_LEVEL = "  "

local DEFAULT_LEAST_URGENT_PRIORITY = 4

function M.labels_of(object)
  return type(object.labels) == "table" and object.labels or {}
end

function M.due_of(object)
  return text(dam_object.task(object).due)
end

local PRIORITY_GROUPS = { "DamPriority1", "DamPriority2", "DamPriority3" }

local BADGE_GAP = "  "

local function is_before(due, today)
  return today ~= nil and due:sub(1, #today) < today
end

function M.badges(object, today)
  local badges = {}

  local due = M.due_of(object)
  if due ~= "" then
    badges[#badges + 1] = { text = "(" .. due .. ")", group = is_before(due, today) and "DamOverdue" or "DamDue" }
  end

  local priority = tonumber(dam_object.task(object).priority)
  if priority and priority < DEFAULT_LEAST_URGENT_PRIORITY then
    badges[#badges + 1] = { text = "p" .. priority, group = PRIORITY_GROUPS[priority] }
  end

  for _, label in ipairs(M.labels_of(object)) do
    badges[#badges + 1] = { text = "@" .. text(label), group = "DamLabel" }
  end

  return badges
end

function M.append_badges(parts, object)
  for _, badge in ipairs(M.badges(object)) do
    parts[#parts + 1] = badge.text
  end
end

function M.object_line(object, indent, folded, today)
  local parts, marks, col = {}, {}, 0

  local function add(part, group)
    if #parts > 0 then
      col = col + #BADGE_GAP
    end

    if group then
      marks[#marks + 1] = { col = col, length = #part, group = group }
    end

    parts[#parts + 1] = part
    col = col + #part
  end

  add(indent .. "- " .. text(object.subject))

  for _, badge in ipairs(M.badges(object, today)) do
    add(badge.text, badge.group)
  end

  if location.parse(object.body) then
    add(location.ICON)
  end

  local path = text(object.path)
  if path ~= "" then
    add(path)
  end

  if folded and folded > 0 then
    add(("(+%d)"):format(folded))
  end

  return table.concat(parts, BADGE_GAP), marks
end

function M.title(spec)
  if spec.query and spec.query ~= spec.title then
    return ("dam: %s  (%s)"):format(spec.title, spec.query)
  end

  return "dam: " .. spec.title
end

function M.refusal(spec, err)
  return { M.title(spec), "", "dam refused this view:", "", "  " .. err.message }
end

local function completed_at_of(object)
  return text(dam_object.task(object).completed_at)
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

function M.render(spec, objects, collapsed, today)
  local folds = collapsed or {}
  local index = tree.index(objects or {})

  local lines = { M.title(spec), "" }
  local entries = {}
  local drawn = 0

  local function write(object, depth)
    local path = text(object.path)
    local hidden = folds[path] and tree.descendant_count(index, path) or 0

    local line, marks = M.object_line(object, INDENT_PER_LEVEL:rep(depth), hidden, today)
    lines[#lines + 1] = line
    entries[#lines] = { object = object, location = location.parse(object.body), marks = marks }
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
