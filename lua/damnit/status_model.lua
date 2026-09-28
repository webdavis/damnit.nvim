local M = {}

M.FIELDS = { "subject", "body", "path", "labels", "depends", "reminders", "recurrence" }
M.TASK_FIELDS = { "done", "priority", "due", "deadline" }
M.EVENT_FIELDS = { "start", "end", "timezone", "location", "transparency" }

M.VERBS = { create = "new", update = "changed", delete = "removed" }

local NOTICE_TEXT_BY_KIND = {
  removed_upstream = "removed upstream",
  event_cancelled = "cancelled upstream",
  push_failed = "push failed",
  pull_failed = "pull failed",
  kind_changed = "kind changed upstream",
}

local function present(value)
  if value == nil or value == vim.NIL then
    return nil
  end

  return value
end

local function same(left, right)
  left, right = present(left), present(right)

  if type(left) == "table" or type(right) == "table" then
    return vim.deep_equal(left, right)
  end

  return left == right
end

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

local function fields_an_update_moved(change)
  if change.op ~= "update" then
    return {}
  end

  if vim.islist(present(change.fields)) then
    return change.fields
  end

  return M.changed_fields(change.before, change.after)
end

local function change_entry(change)
  local embedded_fallback = present(change.after) or present(change.before) or {}

  return {
    kind = "change",
    oid = change.oid,
    op = change.op,
    verb = M.VERBS[change.op] or change.op,
    object_kind = present(change.kind) or present(embedded_fallback.kind),
    subject = tostring(present(change.subject) or embedded_fallback.subject or ""),
    path = tostring(present(change.path) or embedded_fallback.path or ""),
    fields = fields_an_update_moved(change),
    before = present(change.before),
    after = present(change.after),
  }
end

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

local function quoted_the_way_dam_quotes(subject)
  return ('"%s"'):format(subject)
end

function M.notice_text(notice)
  local parts = {}

  if type(notice.remote) == "string" then
    parts[#parts + 1] = notice.remote .. ":"
  end

  if type(notice.oid) == "string" then
    parts[#parts + 1] = notice.oid:sub(1, 7)
  end

  parts[#parts + 1] = NOTICE_TEXT_BY_KIND[notice.kind] or tostring(notice.kind)

  if type(notice.subject) == "string" and notice.subject ~= "" then
    parts[#parts + 1] = quoted_the_way_dam_quotes(notice.subject)
  end

  if type(notice.why) == "string" then
    parts[#parts + 1] = notice.why
  end

  return table.concat(parts, " ")
end

local function remote_entry(item)
  return { kind = "remote", remote = item.remote, commits = item.commits }
end

local function notice_entry(item)
  return { kind = "notice", notice_kind = item.kind, text = M.notice_text(item) }
end

local function section_or_nil_when_empty(name, kind, source, make)
  local items = source or {}
  if #items == 0 then
    return nil
  end

  return { name = name, kind = kind, entries = vim.tbl_map(make, items) }
end

local SECTIONS = {
  { heading = "Conflicts", kind = "conflicts", status_field = "conflicts", entry_of = conflict_entry },
  { heading = "Working", kind = "working", status_field = "unstaged", entry_of = change_entry },
  { heading = "Staged", kind = "staged", status_field = "staged", entry_of = change_entry },
  { heading = "Unpushed", kind = "unpushed", status_field = "unpushed", entry_of = remote_entry },
  { heading = "Notices", kind = "notices", status_field = "notices", entry_of = notice_entry },
}

function M.build(status, remotes)
  status = status or {}

  local commits_by_remote = {}
  for _, entry in ipairs(status.unpushed or {}) do
    commits_by_remote[entry.remote] = entry.commits
  end

  local listed = {}
  for _, entry in ipairs((remotes or {}).remotes or {}) do
    local name = present(entry.name) or entry.remote
    listed[#listed + 1] = { remote = name, commits = commits_by_remote[name] or 0 }
  end

  if #listed == 0 then
    for _, entry in ipairs(status.unpushed or {}) do
      listed[#listed + 1] = { remote = entry.remote, commits = entry.commits }
    end
  end

  local remotes_behind = vim.tbl_filter(function(entry)
    return (entry.commits or 0) > 0
  end, status.unpushed or {})

  local sections = {}
  for _, each in ipairs(SECTIONS) do
    local source = each.status_field == "unpushed" and remotes_behind or status[each.status_field]
    sections[#sections + 1] = section_or_nil_when_empty(each.heading, each.kind, source, each.entry_of)
  end

  return {
    sections = sections,
    empty = #sections == 0,
    remotes = listed,
    remotes_known = remotes ~= nil,
  }
end

return M
