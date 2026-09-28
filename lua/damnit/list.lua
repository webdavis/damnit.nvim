local M = {}

local format = require("damnit.list_format")
local message = require("damnit.message")
local tree = require("damnit.tree")

local BUFFER_NAME = "damnit://list"

local entry_by_line = {}

local shown_spec = nil

local objects_on_screen = nil

local collapsed_paths_this_session = {}

local function find_buffer()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == BUFFER_NAME then
      return buf
    end
  end

  return -1
end

local function entry_under_cursor()
  return entry_by_line[vim.api.nvim_win_get_cursor(0)[1]]
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

local function on_screen_in_this_tabpage(buf)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return true
    end
  end

  return false
end

function M.current_spec()
  local buf = find_buffer()
  if buf == -1 or not shown_spec then
    return nil
  end

  if on_screen_in_this_tabpage(buf) then
    return shown_spec
  end

  return nil
end

local function ensure_buffer()
  local buf = find_buffer()
  if buf ~= -1 then
    return buf
  end

  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, BUFFER_NAME)

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "damlist"

  require("damnit.keys").attach(buf, "damlist")

  return buf
end

local function draw(buf, lines, line_entries, objects)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  entry_by_line = line_entries or {}

  objects_on_screen = objects
end

local function render_into(buf, spec, objects)
  local lines, line_entries = format.render(spec, objects, collapsed_paths_this_session)
  draw(buf, lines, line_entries, objects)
end

local function redraw_without_asking_dam()
  local buf = find_buffer()

  if buf ~= -1 and shown_spec and objects_on_screen then
    render_into(buf, shown_spec, objects_on_screen)
  end
end

local function forest()
  return tree.index(objects_on_screen or {})
end

function M.objects_in_view()
  return objects_on_screen or {}
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

  collapsed_paths_this_session[path] = not collapsed_paths_this_session[path] or nil
  redraw_without_asking_dam()
end

function M.forget_folds()
  collapsed_paths_this_session = {}
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

local function dam_knows_no_such_view(err, spec)
  return err and err.kind == "parse" and spec.probing
end

function M.fetch(spec, callback)
  require("damnit.queue").submit({
    args = require("damnit.views").query_args(spec),
    label = "ls",
    on_done = function(data, err)
      if dam_knows_no_such_view(err, spec) then
        require("damnit.views").forget_filter(spec.title)
      end

      callback(data and data.objects or {}, err)
    end,
  })
end

function M.load(spec)
  local buf = ensure_buffer()

  shown_spec = spec
  draw(buf, { format.title(spec), "", "Loading..." })

  M.fetch(spec, function(objects, err)
    if not vim.api.nvim_buf_is_valid(buf) or shown_spec ~= spec then
      return
    end

    if err then
      message.report(err)

      return draw(buf, format.refusal(spec, err))
    end

    render_into(buf, spec, objects)
  end)

  return buf
end

function M.refresh()
  if shown_spec then
    M.load(shown_spec)
  end
end

function M.open(spec)
  vim.api.nvim_win_set_buf(0, ensure_buffer())

  return M.load(spec)
end

return M
