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

---@param change table
---@return table entry
local function change_entry(change)
  local object = present(change.after) or present(change.before) or {}
  local fields = change.op == "update" and M.changed_fields(change.before, change.after) or {}

  return {
    kind = "change",
    oid = change.oid,
    op = change.op,
    verb = M.VERBS[change.op] or change.op,
    subject = tostring(object.subject or ""),
    path = tostring(object.path or ""),
    fields = fields,
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

--- One notice as a line, built from the fields it carries rather than from a
--- shape assumed per kind.
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

  for _, extra in ipairs({ "why", "reason", "detail" }) do
    if type(notice[extra]) == "string" then
      parts[#parts + 1] = notice[extra]
    end
  end

  return table.concat(parts, " ")
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

---@class damnit.Section
---@field name string the heading as it is drawn
---@field kind "conflicts"|"working"|"staged"|"unpushed"|"notices"
---@field entries table[]

---@class damnit.Model
---@field sections damnit.Section[] in the order they are drawn
---@field empty boolean true when no section has an entry
---@field remotes { remote: string, commits: integer }[]

--- The window's model for one status document.
---
--- Conflicts are drawn first because they are the only section that blocks a
--- pull. An empty section is left out entirely, the way `dam status` leaves it
--- out.
---@param status table the decoded `dam status --json`
---@param remotes table? the decoded `dam remote list --json`
---@return damnit.Model
function M.build(status, remotes)
  status = status or {}

  local counts = {}
  for _, entry in ipairs(status.unpushed or {}) do
    counts[entry.remote] = entry.commits
  end

  local listed = {}
  for _, entry in ipairs((remotes or {}).remotes or {}) do
    listed[#listed + 1] = { remote = entry.remote, commits = counts[entry.remote] or 0 }
  end

  if #listed == 0 then
    for _, entry in ipairs(status.unpushed or {}) do
      listed[#listed + 1] = { remote = entry.remote, commits = entry.commits }
    end
  end

  local sections = {}
  for _, built in ipairs({
    section("Conflicts", "conflicts", status.conflicts, conflict_entry),
    section("Working", "working", status.unstaged, change_entry),
    section("Staged", "staged", status.staged, change_entry),
    section("Unpushed", "unpushed", status.unpushed, function(item)
      return { kind = "remote", remote = item.remote, commits = item.commits }
    end),
    section("Notices", "notices", status.notices, function(item)
      return { kind = "notice", notice_kind = item.kind, text = M.notice_text(item) }
    end),
  }) do
    sections[#sections + 1] = built
  end

  return { sections = sections, empty = #sections == 0, remotes = listed }
end

return M
