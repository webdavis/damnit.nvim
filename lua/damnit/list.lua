local M = {}

local fixed_window = require("damnit.fixed_window")
local format = require("damnit.list_format")
local location_edit = require("damnit.location_edit")
local task_buffer = require("damnit.task_buffer")
local tree = require("damnit.tree")
local view = require("damnit.list.view")
local views = require("damnit.views")
local write = require("damnit.write")

local NOTHING_DRAWN = { entry_by_line = {} }

local function shown_here()
  return view.of(vim.api.nvim_get_current_buf()) or NOTHING_DRAWN
end

local function entry_under_cursor()
  return shown_here().entry_by_line[vim.api.nvim_win_get_cursor(0)[1]]
end

function M.object_under_cursor(app)
  local entry = entry_under_cursor()

  if not entry then
    app.say.warn("no object on this line")

    return nil
  end

  return entry.object
end

function M.object_above_cursor()
  local entry_by_line = shown_here().entry_by_line
  local line = vim.api.nvim_win_get_cursor(0)[1]

  for above = line - 1, 1, -1 do
    if entry_by_line[above] then
      return entry_by_line[above].object
    end
  end

  return nil
end

function M.open_under_cursor(app)
  local object = M.object_under_cursor(app)

  if object then
    task_buffer.open(app, object.oid)
  end
end

function M.jump_to_location_under_cursor(app)
  local entry = entry_under_cursor()

  if not entry then
    return app.say.warn("no object on this line")
  end

  location_edit.jump(app, entry.location)
end

local function view_on_screen_in_this_tabpage()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local shown = view.of(vim.api.nvim_win_get_buf(win))

    if shown then
      return shown
    end
  end

  return nil
end

---@return damnit.ListSpec?
function M.current_spec()
  local shown = view.of(vim.api.nvim_get_current_buf()) or view_on_screen_in_this_tabpage()

  return shown and shown.spec
end

local function redraw_without_asking_dam()
  local buf = vim.api.nvim_get_current_buf()
  local shown = view.of(buf)

  if shown and shown.objects then
    view.render(buf, shown, shown.objects)
  end
end

local function forest()
  return tree.index(M.objects_in_view())
end

function M.objects_in_view()
  return shown_here().objects or {}
end

function M.path_under_cursor()
  local entry = entry_under_cursor()

  return entry and tostring(entry.object.path or "") or ""
end

function M.children_of(path)
  return forest().children[tostring(path)] or {}
end

function M.toggle_fold(app)
  local object = M.object_under_cursor(app)
  if not object then
    return
  end

  local path = tostring(object.path or "")
  if #M.children_of(path) == 0 then
    return app.say.info("nothing is nested here")
  end

  local collapsed = shown_here().collapsed
  collapsed[path] = not collapsed[path] or nil
  redraw_without_asking_dam()
end

function M.write(app, args, label, said)
  write.submit(app, {
    args = args,
    label = label,
    on_ok = function()
      if said then
        app.say.info(said)
      end
    end,
    refresh = M.refresh,
  })
end

---@param spec damnit.ListSpec
function M.fetch(app, spec, callback)
  app.queue.submit({
    args = views.query_args(spec),
    label = "ls",
    on_done = function(data, err)
      callback(data and data.objects or {}, err)
    end,
  })
end

local function load_into(app, buf, shown)
  view.belong_to(shown, app.store)

  if view.nothing_drawn_yet(buf) then
    view.draw(buf, shown, { format.title(shown.spec), "", "Loading..." })
  end

  M.fetch(app, shown.spec, function(objects, err)
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    if err then
      app.say.report(err)

      return view.draw(buf, shown, format.refusal(shown.spec, err))
    end

    view.render(buf, shown, objects)
  end)
end

function M.refresh(app)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local shown = view.of(buf)

    if shown and #vim.fn.win_findbuf(buf) > 0 then
      load_into(app, buf, shown)
    end
  end
end

---@param spec damnit.ListSpec
function M.open(app, spec)
  local buf, shown = view.ensure(spec)

  fixed_window.leave()
  vim.api.nvim_win_set_buf(0, buf)
  load_into(app, buf, shown)

  return buf
end

return M
