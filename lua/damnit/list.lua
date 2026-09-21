-- A list of dam objects as a buffer.
--
-- The buffer is an unlisted scratch buffer put in the current window, which is
-- the plainest thing that works: it is a normal buffer, so every window
-- command, search and motion applies to it, and it needs no layout of its own.
--
-- There is one list buffer, reused, because a second one would be a second
-- thing to refresh. Opening another view redraws it.
--
-- It is not editable: the line an object sits on is a rendering, and the way to
-- change an object is `<CR>`, which opens the task buffer.

local M = {}

local format = require("damnit.list_format")
local message = require("damnit.message")
local tree = require("damnit.tree")

local NAME = "damnit://list"

--- The object and the location each line holds, for the buffer as it stands.
--- Nothing reads an oid out of the text, so the rendering is free to change
--- without breaking a key.
---@type table<integer, damnit.ListEntry>
local entries = {}

--- What the buffer was last opened with, which is what a refresh repeats.
---@type damnit.ListSpec?
local shown = nil

--- The objects the lines on screen were drawn from, so a fold can redraw them
--- without asking dam again.
---@type table[]?
local drawn_from = nil

--- The paths whose children are folded away.
---
--- The session's, not the buffer's: every write here re-reads the view, so a
--- set tied to the lines on screen would unfold the whole tree on every
--- keypress.
---@type table<string, boolean>
local collapsed = {}

---@return integer buf or -1
local function find_buffer()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == NAME then
      return buf
    end
  end

  return -1
end

---@return damnit.ListEntry?
local function entry_under_cursor()
  return entries[vim.api.nvim_win_get_cursor(0)[1]]
end

--- The object the cursor is on, or nil after saying there is none.
---
--- This is what every key acts on, and it answers with the object dam gave
--- rather than with the line, so nothing reads the rendering.
---@return table?
function M.object_under_cursor()
  local entry = entry_under_cursor()

  if not entry then
    message.warn("no object on this line")

    return nil
  end

  return entry.object
end

--- The object on the nearest line above the cursor holding one.
---@return table?
function M.object_above_cursor()
  local line = vim.api.nvim_win_get_cursor(0)[1]

  for above = line - 1, 1, -1 do
    if entries[above] then
      return entries[above].object
    end
  end

  return nil
end

--- Open the object on the cursor's line as a task buffer.
function M.open_under_cursor()
  local object = M.object_under_cursor()

  if object then
    require("damnit.task_buffer").open(object.oid)
  end
end

--- Jump to the code the object on the cursor's line was captured from.
---
--- The body is text a person can edit on their phone, so a line whose object
--- carries no location says so, and so does one whose file or line has moved.
function M.jump_to_location_under_cursor()
  local entry = entry_under_cursor()

  if not entry then
    return message.warn("no object on this line")
  end

  require("damnit.location").jump(entry.location)
end

--- The view the list buffer is showing, when it is on screen in this tabpage.
---
--- The picker asks so that a search made while a filtered view is up searches
--- inside that view. A buffer that exists but is in no window here is not what
--- the operator is looking at, so it answers with nothing.
---@return damnit.ListSpec?
function M.current_spec()
  local buf = find_buffer()
  if buf == -1 or not shown then
    return nil
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return shown
    end
  end

  return nil
end

---@return integer buf
local function ensure_buffer()
  local buf = find_buffer()
  if buf ~= -1 then
    return buf
  end

  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, NAME)

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "damlist"

  require("damnit.keys").attach(buf, "damlist")

  return buf
end

---@param buf integer
---@param lines string[]
---@param line_entries table<integer, damnit.ListEntry>?
---@param objects table[]? the objects those lines were drawn from
local function draw(buf, lines, line_entries, objects)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  entries = line_entries or {}

  -- A loading or refused view was drawn from no answer, so a fold has nothing
  -- to redraw and says there is no object on the line.
  drawn_from = objects
end

---@param buf integer
---@param spec damnit.ListSpec
---@param objects table[]
local function render_into(buf, spec, objects)
  local lines, line_entries = format.render(spec, objects, collapsed)
  draw(buf, lines, line_entries, objects)
end

--- Draw the answer already in hand again, which is what a fold needs: folding
--- changes which lines are written, not what dam holds.
local function redraw()
  local buf = find_buffer()

  if buf ~= -1 and shown and drawn_from then
    render_into(buf, shown, drawn_from)
  end
end

--- The tree the lines on screen were drawn from.
---@return damnit.Tree
local function forest()
  return tree.index(drawn_from or {})
end

--- The objects the lines on screen were drawn from, which is what a key that
--- offers a choice over the whole view reads.
---@return table[]
function M.objects_in_view()
  return drawn_from or {}
end

--- The path the cursor is in: the path of the object on its line, and the root
--- when the line holds none.
---@return string
function M.path_under_cursor()
  local entry = entry_under_cursor()

  return entry and tostring(entry.object.path or "") or ""
end

--- The objects under a path in the view on screen, which is not always every
--- child: a filtered view can match a parent and none of its children.
---@param path string
---@return table[]
function M.children_of(path)
  return forest().children[tostring(path)] or {}
end

--- Fold or unfold the children of the object on the cursor.
---
--- The whole subtree goes, not one level of it, and the line the cursor is on
--- says how many objects went with it.
function M.toggle_fold()
  local object = M.object_under_cursor()
  if not object then
    return
  end

  local path = tostring(object.path or "")
  if #M.children_of(path) == 0 then
    return message.say("nothing is nested here")
  end

  collapsed[path] = not collapsed[path] or nil
  redraw()
end

--- Unfold everything. The folds are the session's, so nothing in the plugin
--- calls this; a spec does, to start from a tree with none.
function M.forget_folds()
  collapsed = {}
end

--- Queue one write, report a failure, and re-read the view on screen either
--- way. The list shows what dam holds, never what a refused write intended.
---@param args string[]
---@param label string
---@param said string? what to say when the write landed
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

--- Ask dam for one view's objects.
---@param spec damnit.ListSpec
---@param callback fun(objects: table[]?, err: damnit.Error?)
function M.fetch(spec, callback)
  require("damnit.queue").submit({
    args = require("damnit.views").query_args(spec),
    label = "ls",
    on_done = function(data, err)
      -- A bare name that is not a saved filter is parsed as query text, and a
      -- word with no colon is not a term, so dam answers `parse`. That is the
      -- one kind that says the name is a view in neither source: a locked
      -- store, a timeout or a cancel says nothing about it.
      if err and err.kind == "parse" and spec.probing then
        require("damnit.views").forget_filter(spec.title)
      end

      callback(data and data.objects or {}, err)
    end,
  })
end

--- Load one view into the buffer, wherever it already is.
---
--- Returns while the call is still out: the buffer appears at once saying it is
--- loading, and is redrawn when dam answers. A refused view is drawn in dam's
--- own wording, so it cannot be mistaken for a view that matched nothing.
---@param spec damnit.ListSpec
---@return integer buf
function M.load(spec)
  local buf = ensure_buffer()

  shown = spec
  draw(buf, { format.title(spec), "", "Loading..." })

  M.fetch(spec, function(objects, err)
    if not vim.api.nvim_buf_is_valid(buf) or shown ~= spec then
      return
    end

    if err then
      -- The queue has already raised dam's own message; this is the same
      -- message where the operator is looking.
      message.report(err)

      return draw(buf, format.refusal(spec, err))
    end

    render_into(buf, spec, objects)
  end)

  return buf
end

--- Ask dam again for the view the buffer is holding, in place: this never
--- touches the current window, so a write made from the picker while another
--- buffer sits in it does not steal that window.
function M.refresh()
  if shown then
    M.load(shown)
  end
end

--- Put one view in the current window.
---@param spec damnit.ListSpec
---@return integer buf
function M.open(spec)
  vim.api.nvim_win_set_buf(0, ensure_buffer())

  return M.load(spec)
end

return M
