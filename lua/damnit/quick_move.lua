local M = {}

local list = require("damnit.list")
local text = require("damnit.object").text
local tree = require("damnit.tree")
local verbs = require("damnit.dam.verbs")

local TOP_LEVEL = ""

local function move_into(app, object, path)
  local args = verbs.mv(object.oid, path)

  list.write(app, args, args[1], ("moved %s"):format(text(object.subject)))
end

local function paths_in_view()
  local paths, seen = {}, {}

  local function offer(path)
    if not seen[path] then
      seen[path] = true
      paths[#paths + 1] = path
    end
  end

  offer(TOP_LEVEL)

  for _, object in ipairs(list.objects_in_view()) do
    local path = text(object.path)

    while path ~= TOP_LEVEL do
      offer(path)
      path = tree.parent_path(path)
    end
  end

  table.sort(paths)

  return paths
end

function M.move(app)
  local object = list.object_under_cursor(app)
  if not object then
    return
  end

  vim.ui.select(paths_in_view(), {
    prompt = "Move into",
    format_item = function(path)
      return path == TOP_LEVEL and "(top level)" or path
    end,
  }, function(path)
    if path == nil then
      return
    end

    move_into(app, object, path)
  end)
end

local function reparent(app, object, destination, refusal)
  if not destination then
    return app.say.warn(refusal)
  end

  move_into(app, object, destination)
end

function M.indent(app)
  local object = list.object_under_cursor(app)
  if not object then
    return
  end

  reparent(app, object, tree.indent_to(object, list.object_above_cursor()))
end

function M.promote(app)
  local object = list.object_under_cursor(app)
  if not object then
    return
  end

  reparent(app, object, tree.promote_to(object, tree.index(list.objects_in_view())))
end

return M
