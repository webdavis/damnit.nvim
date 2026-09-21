-- The text one object looks like in a buffer, and the reading of it back.
--
-- A header of `key: value` lines between two `---` fences and the body as
-- markdown below them. Comment lines inside the header start with `#` and are
-- read only: they carry what dam has no edit flag for.
--
-- Pure: no buffer, no call, no notification.

local M = {}

local tree = require("damnit.tree")

M.FENCE = "---"

M.TASK_KEYS = { "subject", "path", "priority", "due", "deadline", "labels", "depends", "recurrence" }
M.EVENT_KEYS = { "subject", "path", "start", "end", "location", "labels", "depends" }

--- The flag that sets a field, and the flag that clears it. `false` means the
--- field cannot be cleared, so an empty value is refused.
local FLAGS = {
  subject = { "--subject", false },
  priority = { "-p", false },
  due = { "--due", "--no-due" },
  deadline = { "--deadline", "--no-deadline" },
  recurrence = { "--recurrence", "--no-recurrence" },
  start = { "--start", false },
  ["end"] = { "--end", false },
  location = { "--location", "--no-location" },
}

---@param value any
---@return string
local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

---@param object table
---@param field string
---@return string
local function field_value(object, field)
  local group = object.kind == "event" and object.event or object.task

  if field == "labels" or field == "depends" then
    return table.concat(object[field] or {}, ", ")
  end

  if object[field] ~= nil then
    return text(object[field])
  end

  return text((group or {})[field])
end

--- One header line. An empty field is `key:` rather than `key: `, so no line
--- carries trailing whitespace an editor would strip back out.
---@param key string
---@param value string
---@return string
local function line_of(key, value)
  if value == "" then
    return key .. ":"
  end

  return ("%s: %s"):format(key, value)
end

--- The keys one object's kind uses.
---@param object table
---@return string[]
function M.keys(object)
  return object.kind == "event" and M.EVENT_KEYS or M.TASK_KEYS
end

--- The lines one object becomes.
---@param object table
---@return string[]
function M.render(object)
  local lines = { M.FENCE }

  for _, key in ipairs(M.keys(object)) do
    lines[#lines + 1] = line_of(key, field_value(object, key))
  end

  -- Read only: dam has no edit flag for reminders, and dam's priority scale is
  -- the reverse of Todoist's.
  lines[#lines + 1] = line_of("# reminders", table.concat(object.reminders or {}, ", "))

  if object.kind ~= "event" then
    lines[#lines + 1] = "# priority: 1 is highest"
  end

  lines[#lines + 1] = M.FENCE
  vim.list_extend(lines, vim.split(text(object.body), "\n", { plain = true }))

  return lines
end

--- Read a buffer back into a header and a body.
---@param lines string[]
---@return table? header key to { value, line }
---@return string? body
---@return string? err
function M.parse(lines)
  if lines[1] ~= M.FENCE then
    return nil, nil, ("the first line must be %s, the header fence"):format(M.FENCE)
  end

  local header, closed = {}, nil

  for index = 2, #lines do
    local line = lines[index]

    if line == M.FENCE then
      closed = index
      break
    end

    if not vim.startswith(line, "#") then
      local key, value = line:match("^(%l[%l_]*):%s*(.-)%s*$")

      if not key then
        return nil, nil, ("line %d is not a `key: value` header line: %s"):format(index, line)
      end

      if header[key] then
        return nil, nil, ("line %d repeats the field `%s`"):format(index, key)
      end

      header[key] = { value = value, line = index }
    end
  end

  if not closed then
    return nil, nil, ("the header has no closing %s fence"):format(M.FENCE)
  end

  return header, table.concat(vim.list_slice(lines, closed + 1), "\n")
end

---@param value string
---@return string[]
local function split(value)
  local items = {}

  for item in value:gmatch("[^,]+") do
    local trimmed = vim.trim(item)

    if trimmed ~= "" then
      items[#items + 1] = trimmed
    end
  end

  return items
end

---@param wanted string[]
---@param held string[]
---@return string[] added
---@return string[] removed
local function set_diff(wanted, held)
  local have, want = {}, {}

  for _, item in ipairs(held) do
    have[item] = true
  end
  for _, item in ipairs(wanted) do
    want[item] = true
  end

  local added, removed = {}, {}

  for _, item in ipairs(wanted) do
    if not have[item] then
      added[#added + 1] = item
    end
  end
  for _, item in ipairs(held) do
    if not want[item] then
      removed[#removed + 1] = item
    end
  end

  return added, removed
end

--- One refusal, on the line the operator is looking at.
---@param message string
---@param entry { value: string, line: integer }
---@return { message: string, line: integer }
local function refuse(message, entry)
  return { message = message, line = entry.line }
end

--- What `dam mv` should be given for a path the buffer changed.
---
--- `dam mv <oid> <to>` puts the object inside `to` and keeps its own last
--- segment, except at the root, where it has none and becomes `to` itself
--- (`relocate`, dam-application). So the argument is the container of the path
--- that was typed, and a typed path that changes the object's own segment is a
--- rename, which dam has no verb for.
---@param entry { value: string, line: integer }
---@param held string
---@return string? destination
---@return { message: string, line: integer }? refusal
local function move_to(entry, held)
  if entry.value:find("//", 1, true) then
    return nil, refuse("`path` has an empty segment", entry)
  end

  if held == "" then
    return entry.value
  end

  if tree.own_segment(entry.value) ~= tree.own_segment(held) then
    return nil,
      refuse(
        ("`path` renames this object from %q to %q, and dam mv only moves one: keep the last segment and change what comes before it"):format(
          tree.own_segment(held),
          tree.own_segment(entry.value)
        ),
        entry
      )
  end

  return tree.parent_path(entry.value)
end

---@param object table
---@param key string
---@param entry { value: string, line: integer }
---@param edit string[] appended to in place
---@return { message: string, line: integer }? refusal
local function append_flags(object, key, entry, edit)
  if key == "labels" or key == "depends" then
    local added, removed = set_diff(split(entry.value), object[key] or {})
    local set = key == "labels" and "--label" or "--depends"
    local clear = key == "labels" and "--unlabel" or "--undepends"

    for _, item in ipairs(added) do
      vim.list_extend(edit, { set, item })
    end
    for _, item in ipairs(removed) do
      vim.list_extend(edit, { clear, item })
    end

    return nil
  end

  if entry.value == "" then
    local clear = FLAGS[key][2]

    if not clear then
      return refuse(("`%s` cannot be cleared"):format(key), entry)
    end

    edit[#edit + 1] = clear

    return nil
  end

  vim.list_extend(edit, { FLAGS[key][1], entry.value })

  return nil
end

--- Everything the plugin can refuse without asking dam.
---@param object table
---@param header table
---@return { message: string, line: integer }? refusal
local function refusal_in(object, header)
  local allowed = M.keys(object)

  for key, entry in pairs(header) do
    if not vim.tbl_contains(allowed, key) then
      return refuse(("`%s` is not a field of a %s"):format(key, object.kind or "task"), entry)
    end
  end

  local subject = header.subject
  if subject and subject.value == "" then
    return refuse("`subject` is empty, and an object has to say something", subject)
  end

  local priority = header.priority
  if priority then
    local number = tonumber(priority.value)

    if not number or number % 1 ~= 0 or number < 1 or number > 4 then
      return refuse(
        ("`priority` is %s: it has to be 1, 2, 3 or 4, where 1 is the most urgent"):format(priority.value),
        priority
      )
    end
  end

  local depends = header.depends
  if depends then
    for _, oid in ipairs(split(depends.value)) do
      if not oid:match("^%x%x%x%x%x*$") then
        return refuse(("`%s` is not an oid: at least four hex characters"):format(oid), depends)
      end
    end
  end

  return nil
end

--- What a write should send, given the object dam last described and the buffer
--- as the operator left it.
---
--- Only what changed is sent, which matters most for `due`: dam parses a due
--- string, and a round trip through an unchanged one could move a recurrence.
---@param object table
---@param header table
---@param body string
---@return { edit: string[], move: string? }?
---@return { message: string, line: integer }?
function M.changes(object, header, body)
  local refusal = refusal_in(object, header)
  if refusal then
    return nil, refusal
  end

  local edit, move = {}, nil

  local path = header.path
  if path and path.value ~= field_value(object, "path") then
    local destination, refused = move_to(path, field_value(object, "path"))
    if refused then
      return nil, refused
    end

    move = destination
  end

  for _, key in ipairs(M.keys(object)) do
    local entry = header[key]

    if entry and key ~= "path" and entry.value ~= field_value(object, key) then
      local refused = append_flags(object, key, entry, edit)
      if refused then
        return nil, refused
      end
    end
  end

  if body ~= text(object.body) then
    vim.list_extend(edit, { "--body", body })
  end

  return { edit = edit, move = move }
end

return M
