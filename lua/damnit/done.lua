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
--- the plugin shows them and offers the completion that leaves them where they
--- are. `--children keep` states that answer in the argv, which is what also
--- gets the call through on a machine where `done.interactive` turns a plain
--- `--force` into a question dam will not ask under `--json`.
---@param object table
---@param force boolean
function M.send(object, force)
  local args = { "done", object.oid }

  if force then
    vim.list_extend(args, { "--force", "--children", "keep" })
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

      -- Only a blocked completion has a force that helps. dam refuses `done`
      -- by eighteen other rules, several of which name no blocker at all, so
      -- anything else is reported in dam's own words.
      if err.rule ~= "blocked" or force then
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
