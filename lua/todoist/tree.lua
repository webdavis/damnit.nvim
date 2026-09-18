-- Subtasks as a tree: who is under whom, and where a task goes when it is
-- indented or promoted.
--
-- Pure functions over the tasks the API gave. Nothing here touches a buffer, a
-- request or a notification, so the shape of the tree is testable on its own.
--
-- The API names a task's parent `parent_id`, a string or `null`, and it is
-- always present. `vim.json.decode` turns that null into `vim.NIL`, which is
-- truthy, so every read of the field goes through `parent_of` rather than
-- through `task.parent_id or ""`.

local M = {}

--- The id of a task's parent, or the empty string when it has none.
---@param task table?
---@return string
function M.parent_of(task)
  local parent = task and task.parent_id
  if parent == nil or parent == vim.NIL then
    return ""
  end

  return tostring(parent)
end

---@class todoist.Tree
---@field by_id table<string, table> every task in the view, by id
---@field children table<string, table[]> a task's children, in the API's order

--- Index one view's tasks by id and by parent.
---@param tasks table[]
---@return todoist.Tree
function M.index(tasks)
  local tree = { by_id = {}, children = {} }

  for _, task in ipairs(tasks or {}) do
    tree.by_id[tostring(task.id)] = task
  end

  for _, task in ipairs(tasks or {}) do
    local parent = M.parent_of(task)
    if parent ~= "" and tree.by_id[parent] then
      tree.children[parent] = tree.children[parent] or {}
      table.insert(tree.children[parent], task)
    end
  end

  return tree
end

--- Whether a task heads a tree in this view.
---
--- A task whose parent the view does not hold is one too: a filter can match a
--- subtask without matching its parent, and an orphan drawn at the top level is
--- better than an orphan dropped.
---@param tree todoist.Tree
---@param task table
---@return boolean
function M.is_root(tree, task)
  local parent = M.parent_of(task)

  return parent == "" or tree.by_id[parent] == nil
end

--- How many children a task has in this view.
---@param tree todoist.Tree
---@param id string
---@return integer
function M.child_count(tree, id)
  return #(tree.children[id] or {})
end

--- How many tasks sit under a task in this view, at every depth.
---
--- What a fold hides: `descend` stops at a collapsed node, so the badge on a
--- folded line has to count the whole subtree, not the one level of it
--- `child_count` gives.
---@param tree todoist.Tree
---@param id string
---@return integer
function M.descendant_count(tree, id)
  local count = 0
  for _, child in ipairs(tree.children[id] or {}) do
    count = count + 1 + M.descendant_count(tree, tostring(child.id))
  end
  return count
end

--- Walk a task and its descendants, deepest last, calling `visit` with each
--- task and how far under the root it sits.
---
--- A collapsed task is visited itself and its descendants are not, which is
--- what folding is here: the lines are never drawn rather than hidden.
---@param tree todoist.Tree
---@param task table
---@param collapsed table<string, boolean>
---@param visit fun(task: table, depth: integer)
---@param depth integer?
function M.descend(tree, task, collapsed, visit, depth)
  local level = depth or 0
  visit(task, level)

  local id = tostring(task.id)
  if collapsed[id] then
    return
  end

  for _, child in ipairs(tree.children[id] or {}) do
    M.descend(tree, child, collapsed, visit, level + 1)
  end
end

--- Where `>` sends the task on the cursor: under the task on the row above it.
---
--- The row above is whatever task is drawn there, at whatever depth, which is
--- how the app's own indent behaves: the task becomes that task's child and
--- takes its own children with it, because Todoist moves a subtree whole.
---@param task table
---@param above table? the task on the nearest row above holding one
---@return table? destination a move body, or nil with a reason
---@return string? refusal
function M.indent_to(task, above)
  if not above then
    return nil, "nothing above this task to indent it under"
  end

  if M.parent_of(task) == tostring(above.id) then
    return nil, "already under " .. tostring(above.content)
  end

  return { parent_id = tostring(above.id) }
end

--- Where `<` sends the task on the cursor: out from under its parent, one level
--- up.
---
--- Its old parent's parent when the view holds one, so the task lands beside
--- the parent it just left. Otherwise the section or the project it is already
--- in, which is what makes it top level. A task with no parent has nowhere to
--- go and says so.
---@param task table
---@param tree todoist.Tree
---@return table? destination a move body, or nil with a reason
---@return string? refusal
function M.promote_to(task, tree)
  local parent_id = M.parent_of(task)
  if parent_id == "" then
    return nil, "already at the top level"
  end

  local parent = tree.by_id[parent_id]
  local grandparent = M.parent_of(parent)
  if grandparent ~= "" then
    return { parent_id = grandparent }
  end

  local function id_of(field)
    for _, holder in ipairs({ task, parent }) do
      local value = holder and holder[field]
      if type(value) == "string" and value ~= "" then
        return value
      end
    end

    return nil
  end

  local section_id = id_of("section_id")
  if section_id then
    return { section_id = section_id }
  end

  local project_id = id_of("project_id")
  if project_id then
    return { project_id = project_id }
  end

  return nil, "neither its section nor its project is known here"
end

return M
