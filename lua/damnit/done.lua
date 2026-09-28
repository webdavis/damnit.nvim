local M = {}

local message = require("damnit.message")

local SHORT_OID_LENGTH = 7

local BLOCKED_TASK_INDEX = 1

local FORCE_KEEPING_CHILDREN_WITHOUT_ASKING = { "--force", "--children", "keep" }

local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

function M.blockers(err)
  local found = {}

  for index, oid in ipairs(err.oids or {}) do
    if index > BLOCKED_TASK_INDEX then
      found[#found + 1] = text(oid):sub(1, SHORT_OID_LENGTH)
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

local function report_completion(object, report)
  local rolled_forward = recurring_roll_forward(report)

  if rolled_forward then
    return message.say(rolled_forward)
  end

  message.say("completed " .. text(object.subject))
end

local function forcing_would_help(err, already_forced)
  return err.rule == "blocked" and not already_forced
end

function M.send(object, force)
  local args = { "done", object.oid }

  if force then
    vim.list_extend(args, FORCE_KEEPING_CHILDREN_WITHOUT_ASKING)
  end

  args[#args + 1] = "--json"

  require("damnit.queue").submit({
    args = args,
    label = "done",
    on_done = function(report, err)
      if not err then
        report_completion(object, report)

        return require("damnit.list").refresh()
      end

      if not forcing_would_help(err, force) then
        return message.report(err)
      end

      vim.ui.select({ "Complete it anyway, keeping the children where they are", "Cancel" }, {
        prompt = ("%s is blocked by: %s"):format(
          text(object.oid):sub(1, SHORT_OID_LENGTH),
          table.concat(M.blockers(err), ", ")
        ),
      }, function(choice)
        if choice and vim.startswith(choice, "Complete") then
          M.send(object, true)
        end
      end)
    end,
  })
end

function M.complete()
  local object = require("damnit.list").object_under_cursor()

  if object then
    M.send(object, false)
  end
end

return M
