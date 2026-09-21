-- A model into lines and extmark specs.
--
-- This module knows nothing about dam. It takes a model and hands back lines,
-- each carrying the marks that colour it, so a golden test compares a rendering
-- without opening a window.

local M = {}

M.NAMESPACE = vim.api.nvim_create_namespace("damnit")

--- The display column each field of a change line starts at.
M.COLUMNS = { verb = 2, oid = 11, subject = 20, fields = 48, path = 72 }

--- Every group, and the standard group it links to. No colour is written here,
--- so a colourscheme styles the window with nothing on its side.
M.HIGHLIGHTS = {
  DamHeader = "Title",
  DamSection = "Statement",
  DamOpNew = "DiffAdd",
  DamOpChanged = "DiffChange",
  DamOpRemoved = "DiffDelete",
  DamOid = "Identifier",
  DamSubject = "Normal",
  DamPath = "Directory",
  DamFields = "Comment",
  DamLabel = "Tag",
  DamDue = "Constant",
  DamOverdue = "ErrorMsg",
  DamPriority1 = "ErrorMsg",
  DamPriority2 = "WarningMsg",
  DamPriority3 = "MoreMsg",
  DamPriority4 = "Comment",
  DamRemote = "Special",
  DamNotice = "WarningMsg",
  DamConflict = "ErrorMsg",
  DamDiffOld = "DiffDelete",
  DamDiffNew = "DiffAdd",
  DamRunning = "MoreMsg",
}

local OP_GROUPS = { create = "DamOpNew", update = "DamOpChanged", delete = "DamOpRemoved" }

--- One ASCII column each, so the rendering is the same width whether or not
--- mini.icons is installed.
local FALLBACKS = { task = "-", event = "@", remote = ">", conflict = "!" }
local MINI = {
  task = { "default", "file" },
  event = { "default", "calendar" },
  remote = { "default", "git" },
  conflict = { "default", "error" },
}

--- Declare every group. Called once when the first window opens.
function M.define()
  for group, target in pairs(M.HIGHLIGHTS) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
end

--- mini.icons when it is loaded, the ASCII fallback when it is not. Looked up
--- at render time rather than required at load.
---@param kind string
---@return string
function M.icon(kind)
  local ok, icons = pcall(require, "mini.icons")
  if not ok then
    return FALLBACKS[kind] or "-"
  end

  local args = MINI[kind] or MINI.task
  local glyph = icons.get(args[1], args[2])

  return (type(glyph) == "string" and glyph ~= "" and glyph) or FALLBACKS[kind] or "-"
end

--- A line under construction. `add` appends a segment, records its mark and
--- pads out to a display column, so a subject holding wide characters does not
--- shift the columns after it.
local function row()
  local parts, marks, bytes, display = {}, {}, 0, 0

  local function add(text, group, column)
    text = tostring(text)

    if group and #text > 0 then
      marks[#marks + 1] = { col = bytes, length = #text, group = group }
    end

    parts[#parts + 1] = text
    bytes = bytes + #text
    display = display + vim.fn.strdisplaywidth(text)

    if column then
      local fill = ""

      if display < column then
        fill = (" "):rep(column - display)
      elseif display > column then
        -- One space where the segment already overran its column, so a long
        -- subject pushes the next field along rather than running into it.
        fill = " "
      end

      parts[#parts + 1] = fill
      bytes = bytes + #fill
      display = display + #fill
    end
  end

  return {
    add = add,
    line = function(kind, oid)
      return { text = (table.concat(parts):gsub("%s+$", "")), kind = kind, oid = oid, marks = marks }
    end,
  }
end

---@return damnit.Line
local function blank()
  return { text = "", kind = "blank", marks = {} }
end

---@param label string
---@param value string
---@param group string?
---@return damnit.Line
local function header_line(label, value, group)
  local built = row()
  built.add(label, "DamHeader", 9)
  built.add(value, group)

  return built.line("header")
end

--- Naming none is a claim, so it is made only where the list was read. An
--- unread list still names whatever the unpushed rows named.
---@param remotes { remote: string, commits: integer }[]
---@param known boolean
---@return damnit.Line
local function remotes_line(remotes, known)
  if #remotes == 0 then
    return header_line("Remotes:", known and "none configured" or "unknown")
  end

  local built = row()
  built.add("Remotes:", "DamHeader", 9)

  for index, remote in ipairs(remotes) do
    if index > 1 then
      built.add("  ")
    end

    built.add(remote.remote, "DamRemote")
    built.add(remote.commits > 0 and (" (%d unpushed)"):format(remote.commits) or " (clean)")
  end

  return built.line("header")
end

---@param running { label: string, elapsed: number, pending: integer }
---@return damnit.Line
local function running_line(running)
  local built = row()
  built.add("Running:", "DamHeader", 9)
  built.add(("%s  %.1fs"):format(running.label, running.elapsed), "DamRunning")

  if running.pending > 0 then
    built.add(("  (%d queued)"):format(running.pending))
  end

  built.add("     [C-c to cancel]")

  return built.line("header")
end

---@param section damnit.Section
---@return damnit.Line
local function section_line(section)
  local built = row()
  built.add(("%s (%d)"):format(section.name, #section.entries), "DamSection")

  return built.line("section")
end

---@param entry table
---@return damnit.Line
local function change_line(entry)
  local built = row()

  built.add(M.icon(entry.object_kind or "task"))
  built.add(" ", nil, M.COLUMNS.verb)
  built.add(entry.verb, OP_GROUPS[entry.op], M.COLUMNS.oid)
  built.add(entry.oid:sub(1, 7), "DamOid", M.COLUMNS.subject)
  built.add(entry.subject, "DamSubject", M.COLUMNS.fields)

  if #entry.fields > 0 then
    built.add("(" .. table.concat(entry.fields, ", ") .. ")", "DamFields", M.COLUMNS.path)
  else
    built.add("", nil, M.COLUMNS.path)
  end

  built.add(entry.path, "DamPath")

  return built.line("change", entry.oid)
end

---@param entry table
---@return damnit.Line
local function remote_line(entry)
  local built = row()
  built.add(M.icon("remote"))
  built.add(" ", nil, M.COLUMNS.verb)
  built.add(entry.remote, "DamRemote", M.COLUMNS.subject)
  built.add(("%d unpushed"):format(entry.commits))

  return built.line("remote")
end

---@param entry table
---@return damnit.Line
local function conflict_line(entry)
  local built = row()
  built.add(M.icon("conflict"))
  built.add(" ", nil, M.COLUMNS.verb)
  built.add(entry.oid:sub(1, 7), "DamOid", M.COLUMNS.subject)
  built.add(entry.subject, "DamConflict", M.COLUMNS.fields)
  built.add(entry.remote, "DamRemote")

  return built.line("conflict", entry.oid)
end

---@param entry table
---@return damnit.Line
local function notice_line(entry)
  local built = row()
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

---@class damnit.Line
---@field text string the line as it is written to the buffer
---@field kind string what the line is, which drives folds and the keys
---@field oid string? the object this line stands for
---@field section string? the section kind that owns this line
---@field marks { col: integer, length: integer, group: string }[]

--- The lines one model becomes.
---@param model damnit.Model
---@param state { store: string, running: { label: string, elapsed: number, pending: integer }? }
---@return damnit.Line[]
function M.lines(model, state)
  local lines = { header_line("Store:", state.store), remotes_line(model.remotes, model.remotes_known) }

  if state.running then
    lines[#lines + 1] = running_line(state.running)
  end

  lines[#lines + 1] = header_line("Help:", "g?")
  lines[#lines + 1] = blank()

  if model.empty then
    lines[#lines + 1] = { text = "nothing staged, nothing changed", kind = "empty", marks = {} }

    return lines
  end

  for _, section in ipairs(model.sections) do
    local heading = section_line(section)
    heading.section = section.kind
    lines[#lines + 1] = heading

    for _, entry in ipairs(section.entries) do
      local line = ENTRY_LINES[entry.kind](entry)
      line.section = section.kind
      lines[#lines + 1] = line
    end

    lines[#lines + 1] = blank()
  end

  return lines
end

--- Colour a run of lines, clearing whatever the rows held before.
---
--- Replacing a buffer's lines takes their extmarks with them, so every writer
--- of those rows re-marks them.
---@param buf integer
---@param lines damnit.Line[] the lines now occupying the rows
---@param from integer the zero-based row `lines[1]` sits on
function M.mark(buf, lines, from)
  vim.api.nvim_buf_clear_namespace(buf, M.NAMESPACE, from, from + #lines)

  for index, line in ipairs(lines) do
    for _, mark in ipairs(line.marks) do
      vim.api.nvim_buf_set_extmark(buf, M.NAMESPACE, from + index - 1, mark.col, {
        end_col = mark.col + mark.length,
        hl_group = mark.group,
      })
    end
  end
end

--- Put the lines in a buffer and colour them.
---
--- The buffer is unmodifiable, so the write is bracketed. Every mark is cleared
--- and reapplied, because the whole buffer is redrawn rather than patched.
---@param buf integer
---@param lines damnit.Line[]
function M.draw(buf, lines)
  local text, kinds, oids, sections = {}, {}, {}, {}

  -- `false` rather than nil on a line that has none: a buffer variable turns a
  -- hole into vim.NIL, which is truthy, and drops a trailing one, so the line
  -- numbers would stop lining up with the buffer's.
  for index, line in ipairs(lines) do
    text[index] = line.text
    kinds[index] = line.kind
    oids[index] = line.oid or false
    sections[index] = line.section or false
  end

  -- Recorded before the text: the fold expression reads the kinds, and replacing
  -- the lines is what makes Neovim recompute the fold levels.
  vim.b[buf].damnit_kinds = kinds
  vim.b[buf].damnit_oids = oids
  vim.b[buf].damnit_sections = sections

  -- Replacing every line carries a virtual-line mark past the last row, where a
  -- ranged clear no longer reaches it, so the whole namespace goes first.
  vim.api.nvim_buf_clear_namespace(buf, M.NAMESPACE, 0, -1)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].modifiable = false

  M.mark(buf, lines, 0)
end

return M
