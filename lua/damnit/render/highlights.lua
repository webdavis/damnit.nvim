local M = {}

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
  DamRemote = "Special",
  DamNotice = "WarningMsg",
  DamConflict = "ErrorMsg",
  DamDiffOld = "DiffDelete",
  DamDiffNew = "DiffAdd",
  DamRunning = "MoreMsg",
  DamLegend = "Comment",
}

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

return M
