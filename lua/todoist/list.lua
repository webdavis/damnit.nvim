-- A list of tasks as a buffer.
--
-- The buffer is an unlisted scratch buffer put in the current window, which is
-- the plainest thing that works: it is a normal buffer, so every window command,
-- search and motion applies to it, and it needs no layout of its own. The
-- sidebar puts this same buffer in a window of its own rather than a second
-- rendering of it.
--
-- There is one list buffer, reused, because a second one would be a second thing
-- to refresh. Opening another view redraws it.
--
-- It is not editable: the line a task sits on is a rendering, and the way to
-- change a task is `<CR>`, which opens the task buffer the previous task built.

local M = {}

local client = require("todoist.client")
local format = require("todoist.list_format")
local tree = require("todoist.tree")

local NAME = "todoist://list"

--- The task id each line holds, for the buffer as it stands. Nothing reads an
--- id out of the text, so the rendering is free to change without breaking
--- `<CR>`.
---@type table<integer, string>
local ids = {}

--- The location each line's task was captured from, for the buffer as it
--- stands. Same idea as `ids`: parsed once at render and looked up by line,
--- never read back out of the text on screen.
---@type table<integer, todoist.Location>
local locations = {}

--- The tasks the API last gave, by id. A quick edit needs more of a task than
--- its id: its content for a confirm, its priority to cycle and its labels to
--- toggle. The line tables map a line to an id and this maps that id back to
--- the task, so nothing is parsed out of the text on screen.
---@type table<string, table>
local tasks = {}

--- What the buffer was last opened with, which is what a refresh repeats.
---@type todoist.ListSpec?
local shown = nil

--- The tasks, projects and sections the lines on screen were drawn from, so a
--- fold can redraw them without asking the API again.
---@type { tasks: table[], projects: table[], sections: table[] }?
local drawn_from = nil

--- The tasks whose subtasks are folded away, by task id.
---
--- The session's, not the buffer's: every write here re-reads the view, so a
--- set tied to the lines on screen would unfold the whole tree on every
--- keypress. Keyed by id, so a task stays folded across a refresh and across a
--- change of view.
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

--- Open the task on the cursor's line. A heading or a blank line holds none,
--- and says so rather than opening whatever task is nearest.
function M.open_task_under_cursor()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local id = ids[line]

  if not id then
    return vim.notify("todoist.nvim: no task on this line", vim.log.levels.WARN)
  end

  require("todoist.task_buffer").open(id)
end

--- The task the cursor is on, or nil after saying there is none.
---
--- This is what every quick edit acts on, and it answers with the task the API
--- gave rather than with the line, so a key never reads the rendering.
---@return table?
function M.task_under_cursor()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local task = tasks[ids[line] or ""]

  if not task then
    vim.notify("todoist.nvim: no task on this line", vim.log.levels.WARN)
    return nil
  end

  return task
end

--- Jump to the code the task on the cursor's line was captured from.
---
--- The description is text a person can edit on their phone, so a line whose
--- task carries no location says so, and so does one whose file or line has
--- since moved.
function M.jump_to_location_under_cursor()
  local line = vim.api.nvim_win_get_cursor(0)[1]

  if not ids[line] then
    return vim.notify("todoist.nvim: no task on this line", vim.log.levels.WARN)
  end

  require("todoist.location").jump(locations[line])
end

--- The view the list buffer is showing, when it is on screen in this tabpage.
---
--- The picker asks so that a search made while a filtered view is up searches
--- inside that filter. A buffer that exists but is in no window here is not
--- what the operator is looking at, so it answers with nothing and the caller
--- falls back to every open task.
---@return todoist.ListSpec? spec
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

--- Ask the API again for the view the buffer is holding, in place: this never
--- touches the current window, so a quick edit made from the picker while
--- another buffer sits in it does not steal that window.
function M.refresh()
  if shown then
    M.load(shown)
  end
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
  vim.bo[buf].filetype = "todoist-list"

  vim.keymap.set("n", "<CR>", M.open_task_under_cursor, { buffer = buf, desc = "Todoist: open this task" })
  vim.keymap.set("n", "R", M.refresh, { buffer = buf, desc = "Todoist: refresh this view" })
  vim.keymap.set("n", "gd", M.jump_to_location_under_cursor, {
    buffer = buf,
    desc = "Todoist: jump to the code this task was captured from",
  })
  vim.keymap.set("n", "za", M.toggle_fold, { buffer = buf, desc = "Todoist: fold or unfold this task's subtasks" })
  vim.keymap.set("n", ">", M.indent, { buffer = buf, desc = "Todoist: make this task a subtask of the one above" })
  vim.keymap.set("n", "<", M.promote, { buffer = buf, desc = "Todoist: move this task out from under its parent" })
  vim.keymap.set("n", "S", function()
    require("todoist.send").send()
  end, { buffer = buf, desc = "Todoist: send this task to the agent" })
  require("todoist.quick_edit").attach(buf)

  return buf
end

---@param buf integer
---@param lines string[]
---@param line_ids table<integer, string>?
---@param line_locations table<integer, todoist.Location>?
---@param shown_tasks table[]? the tasks those lines were drawn from
local function draw(buf, lines, line_ids, line_locations, shown_tasks)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  ids = line_ids or {}
  locations = line_locations or {}

  tasks = {}
  for _, task in ipairs(shown_tasks or {}) do
    tasks[tostring(task.id)] = task
  end

  -- A loading or refused view was drawn from no answer, so a fold has nothing
  -- to redraw and says there is no task on the line.
  if not shown_tasks then
    drawn_from = nil
  end
end

--- Draw one answer from the API, folds and all.
---@param buf integer
---@param spec todoist.ListSpec
---@param data { tasks: table[], projects: table[], sections: table[] }
local function render_into(buf, spec, data)
  local lines, line_ids, line_locations = format.render(spec, data.tasks, data.projects, data.sections, collapsed)
  draw(buf, lines, line_ids, line_locations, data.tasks)
end

--- Draw the answer already in hand again, which is what a fold needs: folding
--- changes which lines are written, not what the server holds.
local function redraw()
  local buf = find_buffer()
  if buf ~= -1 and shown and drawn_from then
    render_into(buf, shown, drawn_from)
  end
end

--- The tree the lines on screen were drawn from.
---@return todoist.Tree
local function forest()
  return tree.index(drawn_from and drawn_from.tasks or {})
end

--- The tasks under a task in the view on screen.
---
--- What the view holds, which is not always every subtask a task has: a
--- filtered view can match a parent and none of its children.
---@param id string
---@return table[]
function M.children_of(id)
  return forest().children[tostring(id)] or {}
end

--- Fold or unfold the subtasks of the task on the cursor.
---
--- The whole subtree goes, not one level of it, and the line the cursor is on
--- says how many tasks went with it.
function M.toggle_fold()
  local task = M.task_under_cursor()
  if not task then
    return
  end

  local id = tostring(task.id)
  if #M.children_of(id) == 0 then
    return vim.notify("todoist.nvim: no subtasks here", vim.log.levels.INFO)
  end

  if collapsed[id] then
    collapsed[id] = nil
  else
    collapsed[id] = true
  end

  redraw()
end

--- Unfold everything. The folds are the session's, so nothing here calls this:
--- a spec does, to start from a tree with none.
function M.forget_folds()
  collapsed = {}
end

--- The task on the nearest line above the cursor holding one.
---@return table?
function M.task_above_cursor()
  local line = vim.api.nvim_win_get_cursor(0)[1]

  for above = line - 1, 1, -1 do
    local task = tasks[ids[above] or ""]
    if task then
      return task
    end
  end

  return nil
end

--- What a reparent does with its answer: a refusal is the client's to report
--- and changes nothing on screen, and a success re-reads the view.
---@param done string
---@return fun(data: any?, err: todoist.Error?)
local function moved(done)
  return function(_, err)
    if err then
      return
    end

    M.refresh()
    vim.notify("todoist.nvim: " .. done, vim.log.levels.INFO)
  end
end

--- Move the task on the cursor, or say why it is staying where it is.
---@param task table
---@param destination table?
---@param refusal string?
local function reparent(task, destination, refusal)
  if not destination then
    return vim.notify("todoist.nvim: " .. refusal, vim.log.levels.WARN)
  end

  client.move_task(task.id, destination, moved(("moved %s"):format(tostring(task.content))))
end

--- `>`: make the task on the cursor a subtask of the task on the row above it.
function M.indent()
  local task = M.task_under_cursor()
  if not task then
    return
  end

  reparent(task, tree.indent_to(task, M.task_above_cursor()))
end

--- `<`: move the task on the cursor out from under its parent.
function M.promote()
  local task = M.task_under_cursor()
  if not task then
    return
  end

  reparent(task, tree.promote_to(task, forest()))
end

--- Ask for the tasks and the two things that name their groups at once.
---
--- All three go out together rather than one after another: they do not depend
--- on each other, and a list that waited for three round trips in turn would
--- take three times as long to appear. The first failure is the one reported,
--- and the answers that arrive after it are dropped.
---@param filter string? a Todoist filter query, or nil for every open task
---@param callback fun(data: { tasks: table[], projects: table[], sections: table[] }?, err: todoist.Error?)
function M.fetch(filter, callback)
  local data, pending, failed = {}, 3, false

  local function part(key)
    return function(items, err)
      if failed then
        return
      end

      if err then
        failed = true
        return callback(nil, err)
      end

      data[key] = items
      pending = pending - 1

      if pending == 0 then
        callback(data)
      end
    end
  end

  if filter then
    client.get_tasks_matching(filter, part("tasks"))
  else
    client.get_tasks(part("tasks"))
  end
  client.get_projects(part("projects"))
  client.get_sections(part("sections"))
end

--- Load one view into the buffer, wherever it already is.
---
--- Returns while the requests are still out: the buffer appears at once saying
--- it is loading, and is redrawn when the API answers. A refused filter is drawn
--- in the API's own wording, so it cannot be mistaken for a filter that matched
--- nothing. This never touches a window; `open` is what puts the buffer in one.
---@param spec todoist.ListSpec
---@return integer buf
function M.load(spec)
  local buf = ensure_buffer()

  shown = spec
  draw(buf, { format.title(spec), "", "Loading..." })

  M.fetch(spec.filter, function(data, err)
    if not vim.api.nvim_buf_is_valid(buf) or shown ~= spec then
      return
    end

    if err then
      -- The client has already raised the API's own message; this is the same
      -- message where the operator is looking.
      return draw(buf, format.refusal(spec, err))
    end

    drawn_from = data
    render_into(buf, spec, data)
  end)

  return buf
end

--- Put one view in the current window.
---@param spec todoist.ListSpec
---@return integer buf
function M.open(spec)
  local buf = ensure_buffer()
  vim.api.nvim_win_set_buf(0, buf)

  return M.load(spec)
end

return M
