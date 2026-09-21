-- The quick edits: one key each in the list, and where one needs words, one
-- prompt.
--
-- Every write is followed by a read of the view on screen, so what is drawn
-- comes from dam rather than from a guess at what the write did, and a refused
-- write leaves the lines where they are with dam's own message beside them.
--
-- Nothing here is modal: a prompt is `vim.ui.input` and a picker is
-- `vim.ui.select`, so whatever the operator has configured those to be is what
-- they get.

local M = {}

local message = require("damnit.message")
local tree = require("damnit.tree")

--- dam's scale runs 1 to 4 with 1 the most urgent, which is the reverse of
--- Todoist's. Cycling walks towards urgent and wraps back to the least, which
--- is also what `dam new` gives an object that names none.
local MOST_URGENT = 1
local LEAST_URGENT = 4

--- The path every top-level object shares.
local ROOT = ""

---@param value any
---@return string
local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

---@return table?
local function under_cursor()
  return require("damnit.list").object_under_cursor()
end

--- Send one write and say what it did. `--json` is added here, so no caller
--- can forget it.
---@param args string[] the subcommand and its flags
---@param said string
local function send(args, said)
  local full = vim.list_extend({}, args)
  full[#full + 1] = "--json"

  require("damnit.list").write(full, args[1], said)
end

--- Reopen the object under the cursor.
function M.reopen()
  local object = under_cursor()

  if object then
    send({ "edit", object.oid, "--undone" }, "reopened " .. text(object.subject))
  end
end

--- Remove the object under the cursor, after a yes or no.
---
--- dam keeps no undo for a removal and neither does this, which is why the
--- question is asked at all.
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

    send({ "rm", object.oid }, "removed " .. subject)
  end)
end

--- One step up in urgency, wrapping from the most urgent back to the least.
---@param priority any
---@return integer
function M.cycled(priority)
  local current = tonumber(priority) or LEAST_URGENT

  if current <= MOST_URGENT or current > LEAST_URGENT then
    return LEAST_URGENT
  end

  return current - 1
end

--- Cycle the priority of the object under the cursor.
function M.cycle_priority()
  local object = under_cursor()
  if not object then
    return
  end

  local next_priority = M.cycled(type(object.task) == "table" and object.task.priority or nil)

  send({ "edit", object.oid, "-p", tostring(next_priority) }, "priority p" .. next_priority)
end

--- Set the due date of the object under the cursor from a typed line, which dam
--- parses: one it cannot read comes back in dam's words rather than being
--- guessed at here.
function M.schedule()
  local object = under_cursor()
  if not object then
    return
  end

  vim.ui.input({ prompt = "Due: " }, function(due)
    if not due or vim.trim(due) == "" then
      return
    end

    send({ "edit", object.oid, "--due", due }, "due " .. due)
  end)
end

--- Every label the picker offers: the values dam's declared categories hold,
--- in dam's own order, then any label this object carries that no category
--- lists, so a stray one can still be taken off.
---@param on string[] the labels the object carries
---@param categories table[]? as `dam category list` answered
---@return { name: string, on: boolean }[]
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

--- Toggle one label on the object under the cursor, from a picker of the
--- categories dam's config declares.
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

        send(
          { "edit", object.oid, choice.on and "--unlabel" or "--label", choice.name },
          ("@%s %s"):format(choice.name, choice.on and "off" or "on")
        )
      end)
    end,
  })
end

--- Every path the view on screen reaches, each once: the path of each object
--- and every container above it, plus the top level.
---
--- A container nothing sits at is still a destination, because `>` on a row
--- whose parent the view does not draw moves into exactly such a path.
---@return string[]
function M.paths_in_view()
  local paths, seen = {}, {}

  ---@param path string
  local function offer(path)
    if not seen[path] then
      seen[path] = true
      paths[#paths + 1] = path
    end
  end

  offer(ROOT)

  for _, object in ipairs(require("damnit.list").objects_in_view()) do
    local path = text(object.path)

    while path ~= ROOT do
      offer(path)
      path = tree.parent_path(path)
    end
  end

  table.sort(paths)

  return paths
end

--- Move the object under the cursor into one of the paths the view holds.
---
--- `dam mv` keeps the object's own last segment and joins it onto the path it
--- is given, so the choice is a container rather than a new whole path.
function M.move()
  local object = under_cursor()
  if not object then
    return
  end

  vim.ui.select(M.paths_in_view(), {
    prompt = "Move into",
    format_item = function(path)
      return path == ROOT and "(top level)" or path
    end,
  }, function(path)
    if path == nil then
      return
    end

    send({ "mv", object.oid, path }, ("moved %s"):format(text(object.subject)))
  end)
end

--- Create an object at the path the cursor is in.
function M.add()
  local path = require("damnit.list").path_under_cursor()

  vim.ui.input({ prompt = "New: " }, function(subject)
    if not subject or vim.trim(subject) == "" then
      return
    end

    require("damnit.list").write({ "new", subject, "--path", path, "--json" }, "new", "added " .. vim.trim(subject))
  end)
end

--- Move the object where a reparent says, or say why it is staying put.
---@param object table
---@param destination string?
---@param refusal string?
local function reparent(object, destination, refusal)
  if not destination then
    return message.warn(refusal)
  end

  send({ "mv", object.oid, destination }, ("moved %s"):format(text(object.subject)))
end

--- `>`: move the object under the cursor into the path of the row above it.
function M.indent()
  local object = under_cursor()
  if not object then
    return
  end

  reparent(object, tree.indent_to(object, require("damnit.list").object_above_cursor()))
end

--- `<`: move the object under the cursor out into the path its parent sits in.
function M.promote()
  local object = under_cursor()
  if not object then
    return
  end

  reparent(object, tree.promote_to(object, tree.index(require("damnit.list").objects_in_view())))
end

return M
