-- Subtasks as a tree, which in dam is a tree of paths.
--
-- An object's parent is the object whose path is this one's path with the last
-- segment removed, which is what dam's own `children_of` answers. A view that
-- holds a child and not its parent draws the child at the top level, because a
-- query can match one without the other.
--
-- The root path is the exception: every top-level object shares it, so it
-- names no object and nothing nests under it. dam says the same where it
-- refuses a move into a path that contains the mover.
--
-- Pure: no buffer, no call, no notification.

local M = {}

local ROOT = ""

---@param value any
---@return string
local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

--- The path one level up. `work/parent/child/` becomes `work/parent/`, and a
--- path with one segment becomes the root.
---@param path any
---@return string
function M.parent_path(path)
  local trimmed = (text(path):gsub("/$", ""))
  local parent = trimmed:match("^(.*)/[^/]*$")

  return parent and (parent .. "/") or ROOT
end

--- The object's own last segment, which `dam mv` carries along.
---@param path any
---@return string
function M.own_segment(path)
  return (text(path):gsub("/$", ""):match("([^/]*)$")) or ""
end

---@class damnit.Tree
---@field by_path table<string, table> the object at each path this view holds
---@field children table<string, table[]> a path's objects, in the order dam gave

--- Index one view's objects by path and by parent.
---
--- Two objects can share a path, which dam allows, and the last one indexed
--- wins the parent seat. Both are still drawn: the seat decides only which of
--- them the deeper rows nest under.
---@param objects table[]
---@return damnit.Tree
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

--- Whether an object heads a tree in this view.
---@param index damnit.Tree
---@param object table
---@return boolean
function M.is_root(index, object)
  return index.by_path[M.parent_path(text(object.path))] == nil
end

---@param index damnit.Tree
---@param path string
---@return integer
function M.child_count(index, path)
  return #(index.children[path] or {})
end

--- How many objects sit under this path at every depth, which is what a folded
--- line's badge counts.
---@param index damnit.Tree
---@param path string
---@return integer
function M.descendant_count(index, path)
  local count = 0

  for _, child in ipairs(index.children[path] or {}) do
    count = count + 1 + M.descendant_count(index, text(child.path))
  end

  return count
end

--- Walk an object and its descendants, calling `visit` with each and its depth.
---
--- A collapsed object is visited and its descendants are not, so a fold means
--- lines that were never drawn. An object that does not hold its path's seat is
--- visited the same way: the children hang off the path, so walking them from
--- every object sharing it would draw each of them once per sharer.
---@param index damnit.Tree
---@param object table
---@param collapsed table<string, boolean>
---@param visit fun(object: table, depth: integer)
---@param depth integer?
function M.descend(index, object, collapsed, visit, depth)
  local level = depth or 0
  visit(object, level)

  local path = text(object.path)
  if collapsed[path] or index.by_path[path] ~= object then
    return
  end

  for _, child in ipairs(index.children[path] or {}) do
    M.descend(index, child, collapsed, visit, level + 1)
  end
end

--- Where `>` sends the object on the cursor: into the path of the object on the
--- row above.
---
--- `dam mv <oid> <to>` puts the object inside `to` and keeps its own last
--- segment, so the answer is that row's whole path rather than a path built
--- here. An object at the root has no segment to keep and would land beside the
--- row above rather than under it, and nothing nests under a row that is at the
--- root, so both are refused.
---@param object table
---@param above table?
---@return string? destination
---@return string? refusal
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

--- Where `<` sends it: into the path its parent sits in, one level up.
---@param object table
---@param index damnit.Tree
---@return string? destination
---@return string? refusal
function M.promote_to(object, index)
  local parent = M.parent_path(text(object.path))

  if parent == ROOT or index.by_path[parent] == nil then
    return nil, "already at the top level of this view"
  end

  return M.parent_path(parent)
end

return M
