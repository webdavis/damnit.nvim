-- The shape of a tree, and where a reparent sends an object.
--
-- dam models the tree as `path`: an object's parent is the object whose path is
-- this one's with the last segment removed (`children_of`, dam-application).
-- Pure functions over tables: no buffer, no call.

local tree = require("damnit.tree")

---@param subject string
---@param path string
---@return table
local function object(subject, path)
  return {
    oid = ("%040x"):format(#subject * 7 + #path),
    kind = "task",
    subject = subject,
    body = "",
    path = path,
    labels = {},
    depends = {},
    reminders = {},
    task = { done = false, priority = 4 },
  }
end

local PARENT = object("parent", "work/parent/")
local CHILD = object("child", "work/parent/child/")
local GRANDCHILD = object("grandchild", "work/parent/child/note/")
local OTHER = object("other", "work/other/")
local TOP = object("top", "work/")
local ROOTED = object("rooted", "")

--- Every object a walk visits, as `subject@depth`.
---@param index damnit.Tree
---@param root table
---@param collapsed table<string, boolean>?
---@return string
local function walked(index, root, collapsed)
  local seen = {}

  tree.descend(index, root, collapsed or {}, function(node, depth)
    seen[#seen + 1] = ("%s@%d"):format(node.subject, depth)
  end)

  return table.concat(seen, " ")
end

return {
  ["reads a parent path by dropping the last segment"] = function()
    assert(tree.parent_path("work/parent/child/") == "work/parent/", tree.parent_path("work/parent/child/"))
    assert(tree.parent_path("work/") == "", tree.parent_path("work/"))
    assert(tree.parent_path("") == "", tree.parent_path(""))
    assert(tree.own_segment("work/parent/child/") == "child", tree.own_segment("work/parent/child/"))
    assert(tree.own_segment("") == "", tree.own_segment(""))
  end,

  ["indexes children under the object whose path they extend"] = function()
    local index = tree.index({ PARENT, CHILD, GRANDCHILD, OTHER })

    assert(tree.child_count(index, "work/parent/") == 1, tostring(tree.child_count(index, "work/parent/")))
    assert(tree.descendant_count(index, "work/parent/") == 2, tostring(tree.descendant_count(index, "work/parent/")))
    assert(tree.is_root(index, PARENT), "its parent is not in the view, so it heads the tree")
    assert(not tree.is_root(index, CHILD))
  end,

  ["leaves an object whose parent the view does not hold at the top"] = function()
    local index = tree.index({ CHILD })

    assert(tree.is_root(index, CHILD), "an orphan heads a tree of its own")
  end,

  ["nests nothing under an object sitting at the root, which every one shares"] = function()
    local index = tree.index({ ROOTED, TOP })

    assert(tree.is_root(index, TOP), "work/ is not inside a root object")
    assert(tree.child_count(index, "") == 0, tostring(tree.child_count(index, "")))

    -- An object at the root is its own parent under the path rule, so a walk
    -- that let the root parent anything would never return.
    assert(walked(index, ROOTED) == "rooted@0", walked(index, ROOTED))
  end,

  ["walks an object, then its children, then theirs, and stops at a collapsed one"] = function()
    local index = tree.index({ PARENT, CHILD, GRANDCHILD })

    assert(walked(index, PARENT) == "parent@0 child@1 grandchild@2", walked(index, PARENT))
    assert(walked(index, PARENT, { ["work/parent/"] = true }) == "parent@0", walked(index, PARENT))
    assert(
      walked(index, PARENT, { ["work/parent/child/"] = true }) == "parent@0 child@1",
      walked(index, PARENT, { ["work/parent/child/"] = true })
    )
  end,

  ["walks what is nested under a shared path once, from the object holding the seat"] = function()
    local alpha = object("alpha", "work/")
    local beta = object("beta", "work/")
    local gamma = object("gamma", "work/sub/")
    local index = tree.index({ alpha, beta, gamma })

    assert(tree.is_root(index, alpha) and tree.is_root(index, beta), "both sit at the top of this view")
    assert(index.by_path["work/"] == beta, "the last object indexed at a path holds its seat")

    local drawn = walked(index, alpha) .. " " .. walked(index, beta)
    local seen = select(2, drawn:gsub("gamma@", ""))
    assert(seen == 1, drawn)
  end,

  ["indents by naming the path dam mv keeps the object's own segment under"] = function()
    local destination, refusal = tree.indent_to(CHILD, OTHER)

    assert(destination == "work/other/", tostring(destination) .. " " .. tostring(refusal))
  end,

  ["refuses to indent what is already there, what has no row above, and a root object"] = function()
    local _, already = tree.indent_to(CHILD, PARENT)
    assert(already:find("already under", 1, true), already)

    local _, nothing = tree.indent_to(CHILD, nil)
    assert(nothing:find("nothing above", 1, true), nothing)

    local _, rooted = tree.indent_to(ROOTED, PARENT)
    assert(rooted:find("no path of its own", 1, true), rooted)

    local _, under_root = tree.indent_to(CHILD, ROOTED)
    assert(under_root:find("the root", 1, true), under_root)
  end,

  ["promotes to the container its parent sits in"] = function()
    local destination = tree.promote_to(CHILD, tree.index({ PARENT, CHILD }))

    assert(destination == "work/", tostring(destination))
  end,

  ["refuses to promote what this view already draws at the top"] = function()
    local _, top = tree.promote_to(PARENT, tree.index({ PARENT }))
    assert(top:find("top level", 1, true), top)

    local _, rooted = tree.promote_to(ROOTED, tree.index({ ROOTED }))
    assert(rooted:find("top level", 1, true), rooted)
  end,
}
