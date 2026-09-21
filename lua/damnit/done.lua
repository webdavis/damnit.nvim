-- Completing an object, and the one refusal that needs a conversation.
--
-- dam refuses to complete a parent while a child or a dependency is open and
-- names the blockers, which is the opposite of what Todoist did: the yes or no
-- confirm becomes an explanation and a choice.

local M = {}

local message = require("damnit.message")

--- The short form of an oid, which is the only form a message carries.
local SHORT = 7

---@param value any
---@return string
local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

--- The objects blocking a completion, as dam named them: every oid after the
--- first, which is the task itself.
---@param err damnit.Error
---@return string[]
function M.blockers(err)
  local found = {}

  for index, oid in ipairs(err.oids or {}) do
    if index > 1 then
      found[#found + 1] = text(oid):sub(1, SHORT)
    end
  end

  return found
end

--- The sentence for dam being configured to ask a question no client can
--- answer, or nil when the refusal is a different one.
---@param err damnit.Error
---@param oid string
---@return string?
function M.interactive_refusal(err, oid)
  if err.rule ~= "needs_an_answer" then
    return nil
  end

  return ("dam is configured to ask what happens to the children; run dam done %s --force --interactive in a terminal"):format(
    text(oid):sub(1, SHORT)
  )
end

---@param object table
---@param report table? what `dam done` answered
local function report_completion(object, report)
  -- Completing a recurring task does not complete it: dam rolls it forward and
  -- says so in `result`, and the two are different outcomes.
  local result = text(report and report.result)

  if result ~= "" and result ~= "done" then
    return message.say(result)
  end

  message.say("completed " .. text(object.subject))
end

--- Complete one object.
---
--- dam refuses while a child or a dependency is open and lists the blockers, so
--- the plugin shows them and offers the one disposition it can reach without a
--- terminal. Task 31 adds the other two once dam takes them as flags.
---@param object table
---@param force boolean
function M.send(object, force)
  local args = { "done", object.oid }

  if force then
    args[#args + 1] = "--force"
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

      local interactive = M.interactive_refusal(err, object.oid)
      if interactive then
        return message.warn(interactive)
      end

      if err.kind ~= "refused" or force then
        return message.report(err)
      end

      vim.ui.select({ "Complete it anyway, keeping the children where they are", "Cancel" }, {
        prompt = ("%s is blocked by: %s"):format(text(object.oid):sub(1, SHORT), table.concat(M.blockers(err), ", ")),
      }, function(choice)
        if choice and vim.startswith(choice, "Complete") then
          M.send(object, true)
        end
      end)
    end,
  })
end

--- Complete the object under the cursor.
function M.complete()
  local object = require("damnit.list").object_under_cursor()

  if object then
    M.send(object, false)
  end
end

return M
