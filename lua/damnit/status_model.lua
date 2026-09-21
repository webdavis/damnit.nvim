-- One `dam status --json` document into the window's model.
--
-- Pure: nothing here touches a buffer, a window or a notification, which is
-- what makes the window's shape testable without a window.

local M = {}

--- The order dam's own `changed_fields` reports in.
M.FIELDS = { "subject", "body", "path", "labels", "depends", "reminders", "recurrence" }
M.TASK_FIELDS = { "done", "priority", "due", "deadline" }
M.EVENT_FIELDS = { "start", "end", "timezone", "location", "transparency" }

--- dam's own three verbs for the three ops.
M.VERBS = { create = "new", update = "changed", delete = "removed" }

--- One sentence per notice kind. A notice carries its own fields beyond `kind`,
--- and the line is built from whichever of them are present.
local NOTICES = {
  removed_upstream = "removed upstream",
  event_cancelled = "cancelled upstream",
  push_failed = "push failed",
  pull_failed = "pull failed",
  kind_changed = "kind changed upstream",
}

---@param value any
---@return any
local function present(value)
  if value == nil or value == vim.NIL then
    return nil
  end

  return value
end

---@param left any
---@param right any
---@return boolean
local function same(left, right)
  left, right = present(left), present(right)

  if type(left) == "table" or type(right) == "table" then
    return vim.deep_equal(left, right)
  end

  return left == right
end

--- The field names that differ between two wire objects, in dam's order.
---@param before table?
---@param after table?
---@return string[]
function M.changed_fields(before, after)
  before, after = before or {}, after or {}
  local names = {}

  for _, name in ipairs(M.FIELDS) do
    if not same(before[name], after[name]) then
      names[#names + 1] = name
    end
  end

  for _, group in ipairs({ { "task", M.TASK_FIELDS }, { "event", M.EVENT_FIELDS } }) do
    local left = present(before[group[1]]) or {}
    local right = present(after[group[1]]) or {}

    for _, name in ipairs(group[2]) do
      if not same(left[name], right[name]) then
        names[#names + 1] = name
      end
    end
  end

  return names
end

--- The fields an update moved. dam names them itself in every change row; the
--- comparison stands in for a dam that did not.
---@param change table
---@return string[]
local function fields_of(change)
  if change.op ~= "update" then
    return {}
  end

  if vim.islist(present(change.fields)) then
    return change.fields
  end

  return M.changed_fields(change.before, change.after)
end

--- One change row. dam writes the object's own columns flat on the row, and
--- embeds `before` and `after` only under `--full`, which this plugin does not
--- pass, so the embedded objects stand in only for a dam that wrote no row.
---@param change table
---@return table entry
local function change_entry(change)
  local object = present(change.after) or present(change.before) or {}

  return {
    kind = "change",
    oid = change.oid,
    op = change.op,
    verb = M.VERBS[change.op] or change.op,
    object_kind = present(change.kind) or present(object.kind),
    subject = tostring(present(change.subject) or object.subject or ""),
    path = tostring(present(change.path) or object.path or ""),
    fields = fields_of(change),
    before = present(change.before),
    after = present(change.after),
  }
end

---@param conflict table
---@return table entry
local function conflict_entry(conflict)
  local ours = present(conflict.ours) or {}

  return {
    kind = "conflict",
    oid = conflict.oid,
    remote = conflict.remote,
    subject = tostring(ours.subject or ""),
    ours = present(conflict.ours),
    theirs = present(conflict.theirs),
  }
end

--- One notice as a line, built from the fields it carries.
---@param notice table
---@return string
function M.notice_text(notice)
  local parts = {}

  if type(notice.remote) == "string" then
    parts[#parts + 1] = notice.remote .. ":"
  end

  if type(notice.oid) == "string" then
    parts[#parts + 1] = notice.oid:sub(1, 7)
  end

  parts[#parts + 1] = NOTICES[notice.kind] or tostring(notice.kind)

  -- Quoted the way dam quotes a subject in its own notice lines.
  if type(notice.subject) == "string" and notice.subject ~= "" then
    parts[#parts + 1] = ('"%s"'):format(notice.subject)
  end

  if type(notice.why) == "string" then
    parts[#parts + 1] = notice.why
  end

  return table.concat(parts, " ")
end

---@param item table
---@return table entry
local function remote_entry(item)
  return { kind = "remote", remote = item.remote, commits = item.commits }
end

---@param item table
---@return table entry
local function notice_entry(item)
  return { kind = "notice", notice_kind = item.kind, text = M.notice_text(item) }
end

---@param name string
---@param kind string
---@param source table[]?
---@param make fun(item: table): table
---@return damnit.Section?
local function section(name, kind, source, make)
  local items = source or {}
  if #items == 0 then
    return nil
  end

  return { name = name, kind = kind, entries = vim.tbl_map(make, items) }
end

--- Every section, in the order it is drawn: the heading, its kind, the status
--- field it reads and the entry it makes. Conflicts are first because they are
--- the only section that blocks a pull.
---@type { [1]: string, [2]: string, [3]: string, [4]: fun(item: table): table }[]
local SECTIONS = {
  { "Conflicts", "conflicts", "conflicts", conflict_entry },
  { "Working", "working", "unstaged", change_entry },
  { "Staged", "staged", "staged", change_entry },
  { "Unpushed", "unpushed", "unpushed", remote_entry },
  { "Notices", "notices", "notices", notice_entry },
}

---@class damnit.Section
---@field name string the heading as it is drawn
---@field kind "conflicts"|"working"|"staged"|"unpushed"|"notices"
---@field entries table[]

---@class damnit.Model
---@field sections damnit.Section[] in the order they are drawn
---@field empty boolean true when no section has an entry
---@field remotes { remote: string, commits: integer }[]
---@field remotes_known boolean false when the remote list was never read

--- The window's model for one status document.
---
--- An empty section is left out entirely, the way `dam status` leaves it out.
---@param status table the decoded `dam status --json`
---@param remotes table? the decoded `dam remote list --json`
---@return damnit.Model
function M.build(status, remotes)
  status = status or {}

  local counts = {}
  for _, entry in ipairs(status.unpushed or {}) do
    counts[entry.remote] = entry.commits
  end

  -- dam lists a remote under `name`; `remote` is what its unpushed rows use.
  local listed = {}
  for _, entry in ipairs((remotes or {}).remotes or {}) do
    local name = present(entry.name) or entry.remote
    listed[#listed + 1] = { remote = name, commits = counts[name] or 0 }
  end

  if #listed == 0 then
    for _, entry in ipairs(status.unpushed or {}) do
      listed[#listed + 1] = { remote = entry.remote, commits = entry.commits }
    end
  end

  -- dam writes an unpushed row for every configured remote, zero commits
  -- included, and filters them out of its own human form. The section says what
  -- is behind; the header says what exists.
  local behind = vim.tbl_filter(function(entry)
    return (entry.commits or 0) > 0
  end, status.unpushed or {})

  -- An empty section assigns nil, which is a no-op on append.
  local sections = {}
  for _, each in ipairs(SECTIONS) do
    local source = each[3] == "unpushed" and behind or status[each[3]]
    sections[#sections + 1] = section(each[1], each[2], source, each[4])
  end

  return {
    sections = sections,
    empty = #sections == 0,
    remotes = listed,
    remotes_known = remotes ~= nil,
  }
end

return M
