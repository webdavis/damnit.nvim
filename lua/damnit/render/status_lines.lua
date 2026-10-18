local M = {}

local ago = require("damnit.render.ago")
local dam_object = require("damnit.object")
local highlights = require("damnit.render.highlights")
local keymaps = require("damnit.keymaps")
local row = require("damnit.render.row")

M.COLUMNS = { verb = 2, oid = 11, subject = 20, fields = 48, path = 72 }

---@class damnit.StatusEntry
---@field kind "change"|"conflict"|"remote"|"notice"
---@field oid? string
---@field op? string
---@field verb? string
---@field object_kind? string
---@field subject? string
---@field path? string
---@field fields? string[]
---@field before? table
---@field after? table
---@field remote? string
---@field commits? integer
---@field ours? table
---@field theirs? table
---@field notice_kind? string
---@field text? string

local OP_GROUPS = { create = "DamOpNew", update = "DamOpChanged", delete = "DamOpRemoved" }

local function blank()
  return { text = "", kind = "blank", marks = {} }
end

local function header_line(label, value, group)
  local built = row.new()
  built.add(label, "DamHeader", 9)
  built.add(value, group)

  return built.line("header")
end

local function remotes_line(remotes, list_was_read, now)
  if #remotes == 0 then
    return header_line("Remotes:", list_was_read and "none configured" or "unknown")
  end

  local built = row.new()
  built.add("Remotes:", "DamHeader", 9)

  for index, remote in ipairs(remotes) do
    if index > 1 then
      built.add("  ")
    end

    built.add(remote.remote, "DamRemote")
    local commits = remote.commits > 0 and ("%d unpushed"):format(remote.commits) or "clean"
    built.add((" (%s, %s)"):format(commits, ago.pulled_ago(remote.last_pull, now)))
  end

  return built.line("header")
end

local function running_line(running)
  local built = row.new()
  built.add("Running:", "DamHeader", 9)
  built.add(("%s  %.1fs"):format(running.label, running.elapsed), "DamRunning")

  if running.pending > 0 then
    built.add(("  (%d queued)"):format(running.pending))
  end

  built.add("     [C-c to cancel]")

  return built.line("header")
end

local function legend_line(width)
  local built = row.new()
  built.add(keymaps.legend("damstatus", width), "DamLegend")

  return built.line("header")
end

local function section_line(section)
  local built = row.new()
  built.add(("%s (%d)"):format(section.name, #section.entries), "DamSection")

  return built.line("section")
end

---@param entry damnit.StatusEntry
local function change_line(entry)
  local built = row.new()

  built.add(highlights.icon(entry.object_kind or "task"))
  built.add(" ", nil, M.COLUMNS.verb)
  built.add(entry.verb, OP_GROUPS[entry.op], M.COLUMNS.oid)
  built.add(dam_object.short_oid(entry.oid), "DamOid", M.COLUMNS.subject)
  built.add(entry.subject, "DamSubject", M.COLUMNS.fields)

  if #entry.fields > 0 then
    built.add("(" .. table.concat(entry.fields, ", ") .. ")", "DamFields", M.COLUMNS.path)
  else
    built.add("", nil, M.COLUMNS.path)
  end

  built.add(entry.path, "DamPath")

  return built.line("change", entry.oid)
end

---@param entry damnit.StatusEntry
local function remote_line(entry)
  local built = row.new()
  built.add(highlights.icon("remote"))
  built.add(" ", nil, M.COLUMNS.verb)
  built.add(entry.remote, "DamRemote", M.COLUMNS.subject)
  built.add(("%d unpushed"):format(entry.commits))

  return built.line("remote")
end

---@param entry damnit.StatusEntry
local function conflict_line(entry)
  local built = row.new()
  built.add(highlights.icon("conflict"))
  built.add(" ", nil, M.COLUMNS.verb)
  built.add(dam_object.short_oid(entry.oid), "DamOid", M.COLUMNS.subject)
  built.add(entry.subject, "DamConflict", M.COLUMNS.fields)
  built.add(entry.remote, "DamRemote")

  return built.line("conflict", entry.oid)
end

---@param entry damnit.StatusEntry
local function notice_line(entry)
  local built = row.new()
  built.add("  ")
  built.add(entry.text, "DamNotice")

  return built.line("notice")
end

local ENTRY_LINES = {
  change = change_line,
  remote = remote_line,
  conflict = conflict_line,
  notice = notice_line,
}

function M.lines(model, state)
  local lines = {
    header_line("Store:", state.store),
    remotes_line(model.remotes, model.remotes_known, state.now),
    state.running and running_line(state.running) or legend_line(state.width),
    blank(),
  }

  if model.empty then
    lines[#lines + 1] = { text = "nothing staged, nothing changed", kind = "empty", marks = {} }

    return lines
  end

  for _, section in ipairs(model.sections) do
    local heading = section_line(section)
    heading.section = section.kind
    lines[#lines + 1] = heading

    for nth, entry in ipairs(section.entries) do
      local line = ENTRY_LINES[entry.kind](entry)
      line.section = section.kind
      line.entry = entry
      line.nth = nth
      lines[#lines + 1] = line
    end

    lines[#lines + 1] = blank()
  end

  return lines
end

return M
