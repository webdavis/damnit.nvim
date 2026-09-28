local M = {}

M.NAMESPACE = vim.api.nvim_create_namespace("damnit")

M.COLUMNS = { verb = 2, oid = 11, subject = 20, fields = 48, path = 72 }

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

local ONE_COLUMN_ASCII_ICONS = { task = "-", event = "@", remote = ">", conflict = "!" }
local MINI_ICON_ARGS = {
  task = { "default", "file" },
  event = { "default", "calendar" },
  remote = { "default", "git" },
  conflict = { "default", "error" },
}

function M.define()
  for group, target in pairs(M.HIGHLIGHTS) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
end

function M.icon(kind)
  local ok, icons = pcall(require, "mini.icons")
  if not ok then
    return ONE_COLUMN_ASCII_ICONS[kind] or "-"
  end

  local args = MINI_ICON_ARGS[kind] or MINI_ICON_ARGS.task
  local glyph = icons.get(args[1], args[2])

  return (type(glyph) == "string" and glyph ~= "" and glyph) or ONE_COLUMN_ASCII_ICONS[kind] or "-"
end

local OVERRUN_GAP = " "

local function row()
  local parts, marks, bytes, display = {}, {}, 0, 0

  local function add(text, group, pad_to_display_column)
    text = tostring(text)

    if group and #text > 0 then
      marks[#marks + 1] = { col = bytes, length = #text, group = group }
    end

    parts[#parts + 1] = text
    bytes = bytes + #text
    display = display + vim.fn.strdisplaywidth(text)

    if pad_to_display_column then
      local fill = ""

      if display < pad_to_display_column then
        fill = (" "):rep(pad_to_display_column - display)
      elseif display > pad_to_display_column then
        fill = OVERRUN_GAP
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

local function blank()
  return { text = "", kind = "blank", marks = {} }
end

local function header_line(label, value, group)
  local built = row()
  built.add(label, "DamHeader", 9)
  built.add(value, group)

  return built.line("header")
end

local function remotes_line(remotes, list_was_read)
  if #remotes == 0 then
    return header_line("Remotes:", list_was_read and "none configured" or "unknown")
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

local function section_line(section)
  local built = row()
  built.add(("%s (%d)"):format(section.name, #section.entries), "DamSection")

  return built.line("section")
end

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

local function remote_line(entry)
  local built = row()
  built.add(M.icon("remote"))
  built.add(" ", nil, M.COLUMNS.verb)
  built.add(entry.remote, "DamRemote", M.COLUMNS.subject)
  built.add(("%d unpushed"):format(entry.commits))

  return built.line("remote")
end

local function conflict_line(entry)
  local built = row()
  built.add(M.icon("conflict"))
  built.add(" ", nil, M.COLUMNS.verb)
  built.add(entry.oid:sub(1, 7), "DamOid", M.COLUMNS.subject)
  built.add(entry.subject, "DamConflict", M.COLUMNS.fields)
  built.add(entry.remote, "DamRemote")

  return built.line("conflict", entry.oid)
end

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

local NOT_A_HOLE = false

local function record_line_roles_before_the_text(buf, kinds, oids, sections)
  vim.b[buf].damnit_kinds = kinds
  vim.b[buf].damnit_oids = oids
  vim.b[buf].damnit_sections = sections
end

local function clear_every_mark_including_virtual_lines(buf)
  vim.api.nvim_buf_clear_namespace(buf, M.NAMESPACE, 0, -1)
end

function M.draw(buf, lines)
  local text, kinds, oids, sections = {}, {}, {}, {}

  for index, line in ipairs(lines) do
    text[index] = line.text
    kinds[index] = line.kind
    oids[index] = line.oid or NOT_A_HOLE
    sections[index] = line.section or NOT_A_HOLE
  end

  record_line_roles_before_the_text(buf, kinds, oids, sections)
  clear_every_mark_including_virtual_lines(buf)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].modifiable = false

  M.mark(buf, lines, 0)
end

return M
