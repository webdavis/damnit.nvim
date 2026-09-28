local M = {}

local message = require("damnit.message")
local tree = require("damnit.tree")

local MOST_URGENT = 1
local LEAST_URGENT_AND_DEFAULT = 4

local TOP_LEVEL = ""

local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

local function under_cursor()
  return require("damnit.list").object_under_cursor()
end

local function send_as_json(args, said)
  local full = vim.list_extend({}, args)
  full[#full + 1] = "--json"

  require("damnit.list").write(full, args[1], said)
end

function M.reopen()
  local object = under_cursor()

  if object then
    send_as_json({ "edit", object.oid, "--undone" }, "reopened " .. text(object.subject))
  end
end

function M.reopen_here()
  local spec = require("damnit.list").current_spec()

  local showing_completed_history = spec and spec.flat
  if not showing_completed_history then
    return message.warn("u reopens in the completed history; X reopens an object here")
  end

  M.reopen()
end

function M.delete()
  local object = under_cursor()
  if not object then
    return
  end

  local subject = text(object.subject)

  vim.ui.input({ prompt = ('Remove "%s"? (y/N) '):format(subject) }, function(answer)
    if answer ~= "y" and answer ~= "Y" then
      return
    end

    send_as_json({ "rm", object.oid }, "removed " .. subject)
  end)
end

function M.cycled(priority)
  local current = tonumber(priority) or LEAST_URGENT_AND_DEFAULT

  if current <= MOST_URGENT or current > LEAST_URGENT_AND_DEFAULT then
    return LEAST_URGENT_AND_DEFAULT
  end

  return current - 1
end

function M.cycle_priority()
  local object = under_cursor()
  if not object then
    return
  end

  local next_priority = M.cycled(type(object.task) == "table" and object.task.priority or nil)

  send_as_json({ "edit", object.oid, "-p", tostring(next_priority) }, "priority p" .. next_priority)
end

function M.schedule()
  local object = under_cursor()
  if not object then
    return
  end

  vim.ui.input({ prompt = "Due: " }, function(due)
    if not due or vim.trim(due) == "" then
      return
    end

    send_as_json({ "edit", object.oid, "--due", due }, "due " .. due)
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

function M.labels()
  local object = under_cursor()
  if not object then
    return
  end

  require("damnit.queue").submit({
    args = { "category", "list", "--json" },
    label = "category list",
    on_done = function(data, err)
      if err then
        return message.report(err)
      end

      local on = type(object.labels) == "table" and object.labels or {}
      local choices = M.label_choices(on, data and data.categories)

      if #choices == 0 then
        return message.say("dam's config declares no label categories")
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

        send_as_json(
          { "edit", object.oid, choice.on and "--unlabel" or "--label", choice.name },
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

  for _, object in ipairs(require("damnit.list").objects_in_view()) do
    local path = text(object.path)

    while path ~= TOP_LEVEL do
      offer(path)
      path = tree.parent_path(path)
    end
  end

  table.sort(paths)

  return paths
end

function M.move()
  local object = under_cursor()
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

    send_as_json({ "mv", object.oid, path }, ("moved %s"):format(text(object.subject)))
  end)
end

function M.add()
  local path = require("damnit.list").path_under_cursor()

  vim.ui.input({ prompt = "New: " }, function(subject)
    if not subject or vim.trim(subject) == "" then
      return
    end

    require("damnit.list").write({ "new", subject, "--path", path, "--json" }, "new", "added " .. vim.trim(subject))
  end)
end

local function reparent(object, destination, refusal)
  if not destination then
    return message.warn(refusal)
  end

  send_as_json({ "mv", object.oid, destination }, ("moved %s"):format(text(object.subject)))
end

function M.indent()
  local object = under_cursor()
  if not object then
    return
  end

  reparent(object, tree.indent_to(object, require("damnit.list").object_above_cursor()))
end

function M.promote()
  local object = under_cursor()
  if not object then
    return
  end

  reparent(object, tree.promote_to(object, tree.index(require("damnit.list").objects_in_view())))
end

return M
