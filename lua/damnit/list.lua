local M = {}

local format = require("damnit.list_format")
local message = require("damnit.message")
local redraw = require("damnit.redraw")
local scratch = require("damnit.scratch")
local tree = require("damnit.tree")

local NOTHING_DRAWN = { entry_by_line = {} }

local function buffer_name(spec)
  return "damnit://list/" .. spec.title
end

local function view_of(buf)
  return vim.bo[buf].filetype == "damlist" and scratch.state(buf) or nil
end

local function view()
  return view_of(vim.api.nvim_get_current_buf()) or NOTHING_DRAWN
end

local function entry_under_cursor()
  return view().entry_by_line[vim.api.nvim_win_get_cursor(0)[1]]
end

function M.object_under_cursor()
  local entry = entry_under_cursor()

  if not entry then
    message.warn("no object on this line")

    return nil
  end

  return entry.object
end

function M.object_above_cursor()
  local entry_by_line = view().entry_by_line
  local line = vim.api.nvim_win_get_cursor(0)[1]

  for above = line - 1, 1, -1 do
    if entry_by_line[above] then
      return entry_by_line[above].object
    end
  end

  return nil
end

function M.open_under_cursor()
  local object = M.object_under_cursor()

  if object then
    require("damnit.task_buffer").open(object.oid)
  end
end

function M.jump_to_location_under_cursor()
  local entry = entry_under_cursor()

  if not entry then
    return message.warn("no object on this line")
  end

  require("damnit.location_edit").jump(entry.location)
end

local function view_on_screen_in_this_tabpage()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local shown = view_of(vim.api.nvim_win_get_buf(win))

    if shown then
      return shown
    end
  end

  return nil
end

function M.current_spec()
  local shown = view_of(vim.api.nvim_get_current_buf()) or view_on_screen_in_this_tabpage()

  return shown and shown.spec
end

local function bar_the_current_row_and_cut_long_rows_in_this_window_only()
  vim.wo[0][0].cursorline = true
  vim.wo[0][0].wrap = false
end

local function configure(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "damlist"

  vim.api.nvim_create_autocmd("BufWinEnter", {
    buffer = buf,
    callback = bar_the_current_row_and_cut_long_rows_in_this_window_only,
  })

  require("damnit.keys").attach(buf, "damlist")
end

local function ensure_buffer(spec)
  local buf = scratch.named(buffer_name(spec), configure)
  local shown = scratch.state(buf)

  shown.spec = spec
  shown.collapsed = shown.collapsed or {}

  return buf, shown
end

local function oid_by_line(lines, line_entries)
  local oids = {}

  for index = 1, #lines do
    oids[index] = line_entries[index] and line_entries[index].object.oid or false
  end

  return oids
end

local function draw(buf, shown, lines, line_entries, objects)
  line_entries = line_entries or {}

  redraw.keep_cursor(buf, oid_by_line(lines, line_entries), function()
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end)

  shown.entry_by_line = line_entries
  shown.objects = objects
end

local function render_into(buf, shown, objects)
  local lines, line_entries = format.render(shown.spec, objects, shown.collapsed)
  draw(buf, shown, lines, line_entries, objects)
end

local function redraw_without_asking_dam()
  local buf = vim.api.nvim_get_current_buf()
  local shown = view_of(buf)

  if shown and shown.objects then
    render_into(buf, shown, shown.objects)
  end
end

local function forest()
  return tree.index(M.objects_in_view())
end

function M.objects_in_view()
  return view().objects or {}
end

function M.path_under_cursor()
  local entry = entry_under_cursor()

  return entry and tostring(entry.object.path or "") or ""
end

function M.children_of(path)
  return forest().children[tostring(path)] or {}
end

function M.toggle_fold()
  local object = M.object_under_cursor()
  if not object then
    return
  end

  local path = tostring(object.path or "")
  if #M.children_of(path) == 0 then
    return message.say("nothing is nested here")
  end

  local collapsed = view().collapsed
  collapsed[path] = not collapsed[path] or nil
  redraw_without_asking_dam()
end

function M.write(args, label, said)
  require("damnit.queue").submit({
    args = args,
    label = label,
    on_done = function(_, err)
      if err then
        message.report(err)
      elseif said then
        message.say(said)
      end

      M.refresh()
    end,
  })
end

function M.fetch(spec, callback)
  require("damnit.queue").submit({
    args = require("damnit.views").query_args(spec),
    label = "ls",
    on_done = function(data, err)
      callback(data and data.objects or {}, err)
    end,
  })
end

local function nothing_drawn_yet(buf)
  return vim.api.nvim_buf_line_count(buf) == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

local function load_into(buf, shown)
  if nothing_drawn_yet(buf) then
    draw(buf, shown, { format.title(shown.spec), "", "Loading..." })
  end

  M.fetch(shown.spec, function(objects, err)
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    if err then
      message.report(err)

      return draw(buf, shown, format.refusal(shown.spec, err))
    end

    render_into(buf, shown, objects)
  end)
end

function M.refresh()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local shown = view_of(buf)

    if shown and #vim.fn.win_findbuf(buf) > 0 then
      load_into(buf, shown)
    end
  end
end

function M.open(spec)
  local buf, shown = ensure_buffer(spec)

  require("damnit.sidebar").leave_fixed_window()
  vim.api.nvim_win_set_buf(0, buf)
  load_into(buf, shown)

  return buf
end

return M
