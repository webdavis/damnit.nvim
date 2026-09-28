local M = {}

local ROOT = ""

local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

function M.parent_path(path)
  local trimmed = (text(path):gsub("/$", ""))
  local parent = trimmed:match("^(.*)/[^/]*$")

  return parent and (parent .. "/") or ROOT
end

function M.own_segment(path)
  return (text(path):gsub("/$", ""):match("([^/]*)$")) or ""
end

function M.index(objects)
  local index = { by_path = {}, children = {} }

  for _, object in ipairs(objects or {}) do
    local path = text(object.path)

    if path ~= ROOT then
      index.by_path[path] = object
    end
  end

  for _, object in ipairs(objects or {}) do
    local parent = M.parent_path(text(object.path))

    if parent ~= ROOT and index.by_path[parent] then
      index.children[parent] = index.children[parent] or {}
      table.insert(index.children[parent], object)
    end
  end

  return index
end

function M.is_root(index, object)
  return index.by_path[M.parent_path(text(object.path))] == nil
end

function M.child_count(index, path)
  return #(index.children[path] or {})
end

function M.descendant_count(index, path)
  local count = 0

  for _, child in ipairs(index.children[path] or {}) do
    count = count + 1 + M.descendant_count(index, text(child.path))
  end

  return count
end

local function holds_the_seat_of_its_path(index, object, path)
  return index.by_path[path] == object
end

function M.descend(index, object, collapsed, visit, depth)
  local level = depth or 0
  visit(object, level)

  local path = text(object.path)
  if collapsed[path] or not holds_the_seat_of_its_path(index, object, path) then
    return
  end

  for _, child in ipairs(index.children[path] or {}) do
    M.descend(index, child, collapsed, visit, level + 1)
  end
end

function M.indent_to(object, above)
  if not above then
    return nil, "nothing above this object to indent it under"
  end

  local path = text(object.path)
  if path == ROOT then
    return nil, "this object has no path of its own to nest under another"
  end

  local destination = text(above.path)
  if destination == ROOT then
    return nil,
      ("%s is at the root, which every object shares, so nothing nests under it"):format(tostring(above.subject))
  end

  if M.parent_path(path) == destination then
    return nil, "already under " .. tostring(above.subject)
  end

  return destination
end

function M.promote_to(object, index)
  local parent = M.parent_path(text(object.path))

  if parent == ROOT or index.by_path[parent] == nil then
    return nil, "already at the top level of this view"
  end

  return M.parent_path(parent)
end

return M
