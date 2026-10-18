local M = {}

M.SHORT_OID_LENGTH = 7

local IN_EVERY_HEADER = { task = true, event = true }
local IN_THE_TASK_HEADER = { task = true }
local IN_THE_EVENT_HEADER = { event = true }
local IN_NO_HEADER = {}

local SCHEMA = {
  { name = "subject", group = "object", header = IN_EVERY_HEADER },
  { name = "body", group = "object", header = IN_NO_HEADER },
  { name = "path", group = "object", header = IN_EVERY_HEADER },
  { name = "done", group = "task", header = IN_THE_TASK_HEADER },
  { name = "priority", group = "task", header = IN_THE_TASK_HEADER },
  { name = "due", group = "task", header = IN_THE_TASK_HEADER },
  { name = "deadline", group = "task", header = IN_THE_TASK_HEADER },
  { name = "start", group = "event", header = IN_THE_EVENT_HEADER },
  { name = "end", group = "event", header = IN_THE_EVENT_HEADER },
  { name = "timezone", group = "event", header = IN_NO_HEADER },
  { name = "location", group = "event", header = IN_THE_EVENT_HEADER },
  { name = "labels", group = "object", header = IN_EVERY_HEADER },
  { name = "depends", group = "object", header = IN_EVERY_HEADER },
  { name = "reminders", group = "object", header = IN_NO_HEADER },
  { name = "recurrence", group = "object", header = IN_THE_TASK_HEADER },
  { name = "transparency", group = "event", header = IN_NO_HEADER },
}

local function names_where(keep)
  local names = {}

  for _, field in ipairs(SCHEMA) do
    if keep(field) then
      names[#names + 1] = field.name
    end
  end

  return names
end

local function names_in_group(group)
  return names_where(function(field)
    return field.group == group
  end)
end

local function names_in_header(kind)
  return names_where(function(field)
    return field.header[kind] == true
  end)
end

M.FIELDS = { object = names_in_group("object"), task = names_in_group("task"), event = names_in_group("event") }

M.HEADER = { task = names_in_header("task"), event = names_in_header("event") }

function M.present(value)
  if value == vim.NIL then
    return nil
  end

  return value
end

function M.text(value)
  local held = M.present(value)

  return held == nil and "" or tostring(held)
end

function M.short_oid(oid)
  return M.text(oid):sub(1, M.SHORT_OID_LENGTH)
end

function M.task(object)
  return type(object.task) == "table" and object.task or {}
end

function M.event(object)
  return type(object.event) == "table" and object.event or {}
end

function M.header(object)
  return object.kind == "event" and M.HEADER.event or M.HEADER.task
end

return M
