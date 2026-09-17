-- A list of tasks as a buffer.
--
-- The buffer is an unlisted scratch buffer put in the current window, which is
-- the plainest thing that works: it is a normal buffer, so every window command,
-- search and motion applies to it, and it needs no layout of its own. The fixed
-- side split is a different job (a `toggle` command), and it will open this same
-- buffer rather than a second rendering of it.
--
-- There is one list buffer, reused, because a second one would be a second thing
-- to refresh. Opening another view redraws it.
--
-- It is not editable: the line a task sits on is a rendering, and the way to
-- change a task is `<CR>`, which opens the task buffer the previous task built.

local M = {}

local client = require("todoist.client")
local format = require("todoist.list_format")

local NAME = "todoist://list"

--- The task id each line holds, for the buffer as it stands. Nothing reads an
--- id out of the text, so the rendering is free to change without breaking
--- `<CR>`.
---@type table<integer, string>
local ids = {}

--- What the buffer was last opened with, which is what a refresh repeats.
---@type todoist.ListSpec?
local shown = nil

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

--- Ask the API again for the view the buffer is holding.
function M.refresh()
  if shown then
    M.open(shown)
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

  return buf
end

---@param buf integer
---@param lines string[]
---@param line_ids table<integer, string>?
local function draw(buf, lines, line_ids)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  ids = line_ids or {}
end

--- Ask for the tasks and the two things that name their groups at once.
---
--- All three go out together rather than one after another: they do not depend
--- on each other, and a list that waited for three round trips in turn would
--- take three times as long to appear. The first failure is the one reported,
--- and the answers that arrive after it are dropped.
---@param filter string? a Todoist filter query, or nil for every open task
---@param callback fun(data: { tasks: table[], projects: table[], sections: table[] }?, err: todoist.Error?)
local function fetch(filter, callback)
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

--- Put one view in the current window.
---
--- Returns while the requests are still out: the buffer appears at once saying
--- it is loading, and is redrawn when the API answers. A refused filter is drawn
--- in the API's own wording, so it cannot be mistaken for a filter that matched
--- nothing.
---@param spec todoist.ListSpec
---@return integer buf
function M.open(spec)
  local buf = ensure_buffer()
  vim.api.nvim_win_set_buf(0, buf)

  shown = spec
  draw(buf, { format.title(spec), "", "Loading..." })

  fetch(spec.filter, function(data, err)
    if not vim.api.nvim_buf_is_valid(buf) or shown ~= spec then
      return
    end

    if err then
      -- The client has already raised the API's own message; this is the same
      -- message where the operator is looking.
      return draw(buf, format.refusal(spec, err))
    end

    local lines, line_ids = format.render(spec, data.tasks, data.projects, data.sections)
    draw(buf, lines, line_ids)
  end)

  return buf
end

return M
