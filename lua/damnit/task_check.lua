local M = {}

local dam_object = require("damnit.object")
local task_header = require("damnit.task_header")

function M.refuse(message, entry)
  return { message = message, line = entry.line }
end

function M.refusal_in(object, header)
  local allowed = dam_object.header(object)

  for key, entry in pairs(header) do
    if not vim.tbl_contains(allowed, key) then
      return M.refuse(("`%s` is not a field of a %s"):format(key, object.kind or "task"), entry)
    end
  end

  local subject = header.subject
  if subject and subject.value == "" then
    return M.refuse("`subject` is empty, and an object has to say something", subject)
  end

  local priority = header.priority
  if priority then
    local number = tonumber(priority.value)

    if not number or number % 1 ~= 0 or number < 1 or number > 4 then
      return M.refuse(
        ("`priority` is %s: it has to be 1, 2, 3 or 4, where 1 is the most urgent"):format(priority.value),
        priority
      )
    end
  end

  local depends = header.depends
  if depends then
    for _, oid in ipairs(task_header.list_items(depends.value)) do
      if not oid:match("^%x%x%x%x%x*$") then
        return M.refuse(("`%s` is not an oid: at least four hex characters"):format(oid), depends)
      end
    end
  end

  return nil
end

return M
