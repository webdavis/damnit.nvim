local M = {}

local tree = require("damnit.tree")

M.FENCE = "---"

M.TASK_KEYS = { "subject", "path", "done", "priority", "due", "deadline", "labels", "depends", "recurrence" }
M.EVENT_KEYS = { "subject", "path", "start", "end", "location", "labels", "depends" }

local CANNOT_BE_CLEARED = false

local FLAGS = {
  subject = { set = "--subject", clear = CANNOT_BE_CLEARED },
  priority = { set = "-p", clear = CANNOT_BE_CLEARED },
  due = { set = "--due", clear = "--no-due" },
  deadline = { set = "--deadline", clear = "--no-deadline" },
  recurrence = { set = "--recurrence", clear = "--no-recurrence" },
  start = { set = "--start", clear = CANNOT_BE_CLEARED },
  ["end"] = { set = "--end", clear = CANNOT_BE_CLEARED },
  location = { set = "--location", clear = "--no-location" },
}

local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

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

local function header_line_without_trailing_space(key, value)
  if value == "" then
    return key .. ":"
  end

  return ("%s: %s"):format(key, value)
end

function M.keys(object)
  return object.kind == "event" and M.EVENT_KEYS or M.TASK_KEYS
end

function M.render(object)
  local lines = { M.FENCE }

  for _, key in ipairs(M.keys(object)) do
    lines[#lines + 1] = header_line_without_trailing_space(key, field_value(object, key))
  end

  lines[#lines + 1] = header_line_without_trailing_space("# reminders", table.concat(object.reminders or {}, ", "))

  if object.kind ~= "event" then
    lines[#lines + 1] = "# priority: 1 is highest"
  end

  lines[#lines + 1] = M.FENCE
  vim.list_extend(lines, vim.split(text(object.body), "\n", { plain = true }))

  return lines
end

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

local function refuse(message, entry)
  return { message = message, line = entry.line }
end

local function move_to(entry, held_path)
  if entry.value:find("//", 1, true) then
    return nil, refuse("`path` has an empty segment", entry)
  end

  if held_path == "" then
    return entry.value
  end

  if tree.own_segment(entry.value) ~= tree.own_segment(held_path) then
    return nil,
      refuse(
        ("`path` renames this object from %q to %q, and dam mv only moves one: keep the last segment and change what comes before it"):format(
          tree.own_segment(held_path),
          tree.own_segment(entry.value)
        ),
        entry
      )
  end

  return tree.parent_path(entry.value)
end

local function append_flags(object, key, entry, edit)
  if key == "done" then
    if entry.value == "false" then
      edit[#edit + 1] = "--undone"

      return nil
    end

    return refuse("`done` only takes false here, which sends --undone; complete an object with x, or dam done", entry)
  end

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
    local clear = FLAGS[key].clear

    if not clear then
      return refuse(("`%s` cannot be cleared"):format(key), entry)
    end

    edit[#edit + 1] = clear

    return nil
  end

  vim.list_extend(edit, { FLAGS[key].set, entry.value })

  return nil
end

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
