local M = {}

local dam_object = require("damnit.object")
local text = dam_object.text
local list = require("damnit.list")
local verbs = require("damnit.dam.verbs")
local write = require("damnit.write")

local BLOCKED_TASK_INDEX = 1

local DISPOSITIONS = {
  { label = "Complete it anyway, keeping the children where they are", children = "keep" },
  { label = "Complete it anyway, moving the children up one level", children = "up" },
  { label = "Complete it anyway, moving the children into a new group", children = "into" },
  { label = "Cancel" },
}

function M.blockers(err)
  local found = {}

  for index, oid in ipairs(err.oids or {}) do
    if index > BLOCKED_TASK_INDEX then
      found[#found + 1] = dam_object.short_oid(oid)
    end
  end

  return found
end

local function recurring_roll_forward(report)
  local result = text(report and report.result)

  if result ~= "" and result ~= "done" then
    return result
  end
end

local function report_completion(app, object, report)
  local rolled_forward = recurring_roll_forward(report)

  if rolled_forward then
    return app.say.info(rolled_forward)
  end

  app.say.info("completed " .. text(object.subject))
end

local function forcing_would_help(err, already_forced)
  return err.rule == "blocked" and not already_forced
end

local function ask_for_the_group_then_send(app, object)
  vim.ui.input({ prompt = "Name of the group to move the children into: " }, function(name)
    name = vim.trim(name or "")

    if name ~= "" then
      M.send(app, object, "into:" .. name)
    end
  end)
end

function M.send(app, object, children)
  write.submit(app, {
    args = verbs.done(object.oid, children),
    label = "done",
    on_ok = function(report)
      report_completion(app, object, report)
      list.refresh(app)
    end,
    on_error = function(err)
      if not forcing_would_help(err, children) then
        return app.say.report(err)
      end

      vim.ui.select(DISPOSITIONS, {
        format_item = function(item)
          return item.label
        end,
        prompt = ("%s is blocked by: %s"):format(dam_object.short_oid(object.oid), table.concat(M.blockers(err), ", ")),
      }, function(choice)
        if not (choice and choice.children) then
          return
        end

        if choice.children == "into" then
          return ask_for_the_group_then_send(app, object)
        end

        M.send(app, object, choice.children)
      end)
    end,
  })
end

function M.complete(app)
  local object = list.object_under_cursor(app)

  if object then
    M.send(app, object)
  end
end

return M
