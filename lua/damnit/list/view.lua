local M = {}

local format = require("damnit.list_format")
local highlights = require("damnit.render.highlights")
local keymaps = require("damnit.keymaps")
local redraw = require("damnit.redraw")
local render = require("damnit.render")
local scratch = require("damnit.scratch")

local function buffer_name(spec)
  return "damnit://list/" .. spec.title
end

function M.of(buf)
  return vim.bo[buf].filetype == "damlist" and scratch.state(buf) or nil
end

function M.winbar()
  local legend = keymaps.legend("damlist", vim.api.nvim_win_get_width(vim.g.statusline_winid))

  return "%#DamLegend#" .. legend:gsub("%%", "%%%%")
end

local function bar_the_current_row_cut_long_rows_and_show_the_legend_in_this_window_only()
  vim.wo[0][0].cursorline = true
  vim.wo[0][0].wrap = false
  vim.wo[0][0].winbar = "%!v:lua.require'damnit.list.view'.winbar()"
end

local function configure(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "damlist"
  highlights.define()

  vim.api.nvim_create_autocmd("BufWinEnter", {
    buffer = buf,
    callback = bar_the_current_row_cut_long_rows_and_show_the_legend_in_this_window_only,
  })
end

function M.ensure(spec)
  local buf = scratch.named(buffer_name(spec), configure)
  local shown = scratch.state(buf)

  shown.spec = spec
  shown.collapsed = shown.collapsed or {}

  return buf, shown
end

function M.belong_to(shown, store)
  if shown.store ~= store then
    shown.collapsed = {}
    shown.store = store
  end
end

local function rows_of(lines, line_entries)
  local rows = {}

  for index, line in ipairs(lines) do
    rows[index] = { text = line, oid = line_entries[index] and line_entries[index].object.oid }
  end

  return rows
end

local function colour_the_badges(buf, line_entries)
  local namespace = render.NAMESPACE
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)

  for line, entry in pairs(line_entries) do
    for _, mark in ipairs(entry.marks or {}) do
      vim.api.nvim_buf_set_extmark(buf, namespace, line - 1, mark.col, {
        end_col = mark.col + mark.length,
        hl_group = mark.group,
      })
    end
  end
end

function M.draw(buf, shown, lines, line_entries, objects)
  line_entries = line_entries or {}

  redraw.keep_cursor(buf, function()
    scratch.draw(buf, rows_of(lines, line_entries))
  end)
  colour_the_badges(buf, line_entries)

  shown.entry_by_line = line_entries
  shown.objects = objects
end

function M.render(buf, shown, objects)
  local lines, line_entries = format.render(shown.spec, objects, shown.collapsed, os.date("%Y-%m-%d", os.time()))
  M.draw(buf, shown, lines, line_entries, objects)
end

function M.nothing_drawn_yet(buf)
  return vim.api.nvim_buf_line_count(buf) == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

return M
