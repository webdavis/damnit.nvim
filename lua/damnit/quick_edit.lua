local M = {}

local list = require("damnit.list")
local tree = require("damnit.tree")
local verbs = require("damnit.dam.verbs")

local MOST_URGENT = 1
local LEAST_URGENT_AND_DEFAULT = 4

local TOP_LEVEL = ""

local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

local function send(app, args, said)
  list.write(app, args, args[1], said)
end

function M.reopen(app)
  local object = list.object_under_cursor(app)

  if object then
    send(app, verbs.reopen(object.oid), "reopened " .. text(object.subject))
  end
end

function M.reopen_here(app)
  local spec = list.current_spec()

  local showing_completed_history = spec and spec.flat
  if not showing_completed_history then
    return app.say.warn("u reopens in the completed history; X reopens an object here")
  end

  M.reopen(app)
end

function M.delete(app)
  local object = list.object_under_cursor(app)
  if not object then
    return
  end

  local subject = text(object.subject)

  vim.ui.input({ prompt = ('Remove "%s"? (y/N) '):format(subject) }, function(answer)
    if answer ~= "y" and answer ~= "Y" then
      return
    end

    send(app, verbs.rm(object.oid), "removed " .. subject)
  end)
end

function M.cycled(priority)
  local current = tonumber(priority) or LEAST_URGENT_AND_DEFAULT

  if current <= MOST_URGENT or current > LEAST_URGENT_AND_DEFAULT then
    return LEAST_URGENT_AND_DEFAULT
  end

  return current - 1
end

function M.cycle_priority(app)
  local object = list.object_under_cursor(app)
  if not object then
    return
  end

  local next_priority = M.cycled(type(object.task) == "table" and object.task.priority or nil)

  send(app, verbs.priority(object.oid, next_priority), "priority p" .. next_priority)
end

function M.schedule(app)
  local object = list.object_under_cursor(app)
  if not object then
    return
  end

  vim.ui.input({ prompt = "Due: " }, function(due)
    if not due or vim.trim(due) == "" then
      return
    end

    send(app, verbs.due(object.oid, due), "due " .. due)
  end)
end

function M.label_choices(on, categories)
  local choices, seen = {}, {}

  for _, category in ipairs(categories or {}) do
    for _, value in ipairs(category.values or {}) do
      local name = text(value)

      if name ~= "" and not seen[name] then
        seen[name] = true
        choices[#choices + 1] = { name = name, on = vim.tbl_contains(on, name) }
      end
    end
  end

  for _, name in ipairs(on) do
    if not seen[name] then
      choices[#choices + 1] = { name = name, on = true }
    end
  end

  return choices
end

function M.labels(app)
  local object = list.object_under_cursor(app)
  if not object then
    return
  end

  app.queue.submit({
    args = verbs.category_list(),
    label = "category list",
    on_done = function(data, err)
      if err then
        return app.say.report(err)
      end

      local on = type(object.labels) == "table" and object.labels or {}
      local choices = M.label_choices(on, data and data.categories)

      if #choices == 0 then
        return app.say.info("dam's config declares no label categories")
      end

      vim.ui.select(choices, {
        prompt = "Labels",
        format_item = function(choice)
          return ("[%s] %s"):format(choice.on and "x" or " ", choice.name)
        end,
      }, function(choice)
        if not choice then
          return
        end

        send(
          app,
          (choice.on and verbs.unlabel or verbs.label)(object.oid, choice.name),
          ("@%s %s"):format(choice.name, choice.on and "off" or "on")
        )
      end)
    end,
  })
end

function M.paths_in_view()
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

  vim.ui.select(M.paths_in_view(), {
    prompt = "Move into",
    format_item = function(path)
      return path == TOP_LEVEL and "(top level)" or path
    end,
  }, function(path)
    if path == nil then
      return
    end

    send(app, verbs.mv(object.oid, path), ("moved %s"):format(text(object.subject)))
  end)
end

function M.add(app)
  local path = list.path_under_cursor()

  vim.ui.input({ prompt = "New: " }, function(subject)
    if not subject or vim.trim(subject) == "" then
      return
    end

    list.write(app, verbs.new(subject, path), "new", "added " .. vim.trim(subject))
  end)
end

local function reparent(app, object, destination, refusal)
  if not destination then
    return app.say.warn(refusal)
  end

  send(app, verbs.mv(object.oid, destination), ("moved %s"):format(text(object.subject)))
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
