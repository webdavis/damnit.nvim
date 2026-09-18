-- The shape of a tree, and where a reparent sends a task.
--
-- Pure functions over tables: no buffer, no request. Every task here carries a
-- `parent_id`, because the API always sends one, and the top-level ones carry
-- it as `vim.NIL`, which is what `vim.json.decode` makes of a JSON null and is
-- truthy.

local tree = require("todoist.tree")

local PARENT = { id = "p", content = "Ship the release", project_id = "1", section_id = "9", parent_id = vim.NIL }
local CHILD = { id = "c", content = "Tag it", project_id = "1", section_id = "9", parent_id = "p" }
local GRANDCHILD = { id = "g", content = "Sign the tag", project_id = "1", section_id = "9", parent_id = "c" }

---@param tasks table[]
---@return todoist.Tree
local function indexed(tasks)
  return tree.index(tasks)
end

--- Every task a walk visits, as `id@depth`.
---@param forest todoist.Tree
---@param root table
---@param collapsed table<string, boolean>?
---@return string
local function walked(forest, root, collapsed)
  local seen = {}

  tree.descend(forest, root, collapsed or {}, function(task, depth)
    seen[#seen + 1] = ("%s@%d"):format(task.id, depth)
  end)

  return table.concat(seen, " ")
end

return {
  ["reads a null parent as no parent at all"] = function()
    assert(tree.parent_of({ id = "p", parent_id = vim.NIL }) == "")
    assert(tree.parent_of({ id = "p" }) == "")
    assert(tree.parent_of({ id = "c", parent_id = "p" }) == "p")
  end,

  ["a task whose parent is in the view is not a root, and one whose parent is not is"] = function()
    local forest = indexed({ PARENT, CHILD })

    assert(tree.is_root(forest, PARENT))
    assert(not tree.is_root(forest, CHILD))
    assert(tree.is_root(indexed({ CHILD }), CHILD), "an orphan heads a tree of its own")
  end,

  ["a walk visits a task, then its children, then theirs"] = function()
    local forest = indexed({ PARENT, CHILD, GRANDCHILD })

    assert(walked(forest, PARENT) == "p@0 c@1 g@2", walked(forest, PARENT))
  end,

  ["a collapsed task is visited and its descendants are not"] = function()
    local forest = indexed({ PARENT, CHILD, GRANDCHILD })

    assert(walked(forest, PARENT, { p = true }) == "p@0", walked(forest, PARENT, { p = true }))
    assert(walked(forest, PARENT, { c = true }) == "p@0 c@1", walked(forest, PARENT, { c = true }))
  end,

  ["counts the children a task has in this view"] = function()
    local second = { id = "c2", content = "Write the notes", parent_id = "p" }
    local forest = indexed({ PARENT, CHILD, second })

    assert(tree.child_count(forest, "p") == 2, tostring(tree.child_count(forest, "p")))
    assert(tree.child_count(forest, "c") == 0)
  end,

  ["> puts a task under the one above it, whatever level that one is at"] = function()
    local sibling = { id = "s", content = "Draft the notes", parent_id = vim.NIL }

    assert(vim.deep_equal(tree.indent_to(sibling, PARENT), { parent_id = "p" }))
    assert(vim.deep_equal(tree.indent_to(sibling, GRANDCHILD), { parent_id = "g" }))
  end,

  ["> on the first task in the view moves nothing and says why"] = function()
    local destination, refusal = tree.indent_to(PARENT, nil)

    assert(destination == nil)
    assert(refusal:find("nothing above", 1, true), refusal)
  end,

  ["> under the parent it already has moves nothing and says why"] = function()
    local destination, refusal = tree.indent_to(CHILD, PARENT)

    assert(destination == nil)
    assert(refusal:find("already under Ship the release", 1, true), refusal)
  end,

  ["< sends a grandchild beside the parent it left"] = function()
    local forest = indexed({ PARENT, CHILD, GRANDCHILD })

    assert(vim.deep_equal(tree.promote_to(GRANDCHILD, forest), { parent_id = "p" }))
  end,

  ["< sends a child to the section its parent sits in"] = function()
    local forest = indexed({ PARENT, CHILD })

    assert(vim.deep_equal(tree.promote_to(CHILD, forest), { section_id = "9" }))
  end,

  ["< sends a child with no section to its project"] = function()
    local parent = { id = "p", content = "Ship", project_id = "1", parent_id = vim.NIL, section_id = vim.NIL }
    local child = { id = "c", content = "Tag it", project_id = "1", parent_id = "p", section_id = vim.NIL }

    assert(vim.deep_equal(tree.promote_to(child, indexed({ parent, child })), { project_id = "1" }))
  end,

  ["< on a top-level task moves nothing and says why"] = function()
    local destination, refusal = tree.promote_to(PARENT, indexed({ PARENT }))

    assert(destination == nil)
    assert(refusal:find("already at the top level", 1, true), refusal)
  end,

  ["< on an orphan makes it top level, since the view holds no parent to climb"] = function()
    local forest = indexed({ CHILD })

    assert(vim.deep_equal(tree.promote_to(CHILD, forest), { section_id = "9" }))
  end,
}
