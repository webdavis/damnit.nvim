-- The text a task looks like in a buffer, and the reading of it back.
--
-- One task is a header of `key: value` lines between two `---` fences and the
-- description as the markdown body below them. That shape is markdown
-- frontmatter, which means the operator already knows it, an editor already
-- highlights it, and a hand that retypes the block by hand produces something
-- this module reads rather than something it guesses at.
--
-- Everything here is a pure function over lines and tables: no buffer, no
-- request, no notification. The buffer module is what has side effects.

local M = {}

--- The fence that opens and closes the header.
M.FENCE = "---"

--- Every header key, in the order they are rendered. A rendered buffer always
--- carries all of them, so a missing one on the way back in is a hand edit that
--- went wrong rather than a field left out on purpose.
M.KEYS = { "content", "due", "priority", "labels", "project", "section" }

--- The keys a write may change. `project` and `section` are shown so the buffer
--- says where the task lives, but moving a task is a different API call than
--- editing one, so an edit to either is refused rather than dropped.
local WRITABLE = { content = true, due = true, priority = true, labels = true }

---@param value any
---@return string
local function text(value)
  -- A JSON null decodes to `vim.NIL`, which every optional field on a task can
  -- be: no section, no description, no due date.
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

--- The due string Todoist last recorded, which is the thing a human edits. The
--- date and the recurrence are derived from it by the API, not by this plugin.
---@param task table
---@return string
local function due_string(task)
  return type(task.due) == "table" and text(task.due.string) or ""
end

---@param task table
---@return string[]
local function labels(task)
  return type(task.labels) == "table" and task.labels or {}
end

--- One header line. An empty field is `key:` rather than `key: `, so no line
--- carries trailing whitespace an editor would strip back out.
---@param key string
---@param value string
---@return string
local function field(key, value)
  if value == "" then
    return key .. ":"
  end

  return ("%s: %s"):format(key, value)
end

--- The lines one task becomes.
---@param task table as the API returned it
---@return string[]
function M.render(task)
  local lines = {
    M.FENCE,
    field("content", text(task.content)),
    field("due", due_string(task)),
    field("priority", text(task.priority or 1)),
    field("labels", table.concat(labels(task), ", ")),
    field("project", text(task.project_id)),
    field("section", text(task.section_id)),
    M.FENCE,
  }

  vim.list_extend(lines, vim.split(text(task.description), "\n", { plain = true }))

  return lines
end

--- Read a buffer back into a header table and the description.
---
--- A refusal names what is wrong with which line, because the operator is
--- looking at the text it is talking about.
---@param lines string[]
---@return table? header keyed by the names in `M.KEYS`
---@return string? description
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

    local key, value = line:match("^(%l[%l_]*):%s*(.-)%s*$")
    if not key then
      return nil, nil, ("line %d is not a `key: value` header line: %s"):format(index, line)
    end

    if not vim.tbl_contains(M.KEYS, key) then
      return nil, nil, ("line %d names an unknown field `%s`"):format(index, key)
    end

    if header[key] then
      return nil, nil, ("line %d repeats the field `%s`"):format(index, key)
    end

    header[key] = value
  end

  if not closed then
    return nil, nil, ("the header has no closing %s fence"):format(M.FENCE)
  end

  local missing = {}
  for _, key in ipairs(M.KEYS) do
    if not header[key] then
      missing[#missing + 1] = key
    end
  end

  if #missing > 0 then
    return nil, nil, ("the header is missing %s"):format(table.concat(missing, ", "))
  end

  return header, table.concat(vim.list_slice(lines, closed + 1), "\n")
end

--- Split a labels line into label names.
---@param value string
---@return string[]
local function split_labels(value)
  local names = {}
  for name in value:gmatch("[^,]+") do
    local trimmed = vim.trim(name)
    if trimmed ~= "" then
      names[#names + 1] = trimmed
    end
  end

  return names
end

---@param left string[]
---@param right string[]
---@return boolean
local function same_list(left, right)
  return table.concat(left, "\0") == table.concat(right, "\0")
end

--- What a write should send, given the task as the API last described it and the
--- buffer as the operator left it.
---
--- Only what changed is sent. A due string in particular is left out when it did
--- not change, because sending it makes Todoist parse it again, and a reparse is
--- what loses a recurrence.
---
--- Local refusals are the ones this plugin can be sure of without asking: an
--- empty content, a priority outside the API's range, and a move dressed up as
--- an edit. Everything else, the due string above all, is the API's to judge,
--- and its answer is better wording than a guess made here.
---@param task table
---@param header table
---@param description string
---@return table? fields empty when nothing changed
---@return string? err
function M.changes(task, header, description)
  for key in pairs(header) do
    if not WRITABLE[key] and header[key] ~= text(task[key .. "_id"]) then
      return nil, ("`%s` cannot be changed here: moving a task is not an edit to it"):format(key)
    end
  end

  if header.content == "" then
    return nil, "`content` is empty, and a task has to say something"
  end

  local priority = tonumber(header.priority)
  if not priority or priority % 1 ~= 0 or priority < 1 or priority > 4 then
    return nil, ("`priority` is %s: it has to be 1, 2, 3 or 4, where 4 is the most urgent"):format(header.priority)
  end

  local fields = {}

  if header.content ~= text(task.content) then
    fields.content = header.content
  end

  if description ~= text(task.description) then
    fields.description = description
  end

  if priority ~= (task.priority or 1) then
    fields.priority = priority
  end

  if header.due ~= due_string(task) then
    fields.due_string = header.due
  end

  local wanted = split_labels(header.labels)
  if not same_list(wanted, labels(task)) then
    fields.labels = wanted
  end

  return fields
end

return M
