-- The completed history as a buffer: newest first, a page at a time, with `u`
-- to reopen the task on the cursor's line.
--
-- It is a buffer of its own rather than the list buffer in another mode. A
-- completed task has no project or section heading over it and no `<CR>` or `gd`
-- of its own, its line is a completion date rather than a due date, and it pages
-- as the cursor reaches the bottom. Two buffers means the list keeps its keys
-- and its line table and neither screen has to ask which mode it is in.
--
-- Paging is driven by the cursor: a page is asked for when the cursor reaches
-- the last task line, once, and nothing is asked for while a request is out or
-- once the walk has read as deep as it goes.

local M = {}

local client = require("todoist.client")
local completed_history = require("todoist.completed_history")

local NAME = "todoist://completed"

--- The task id each line holds, for the buffer as it stands.
---@type table<integer, string>
local ids = {}

--- The walk the buffer is showing. A new one replaces it, and an answer for a
--- walk that is no longer this one is dropped.
---@type table?
local history = nil

--- Whether a page is out. It is what keeps the bottom of the list from asking
--- for the same page once per cursor movement.
local in_flight = false

---@return integer buf or -1
local function find_buffer()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == NAME then
      return buf
    end
  end

  return -1
end

---@param buf integer
---@param lines string[]
---@param line_ids table<integer, string>?
local function draw(buf, lines, line_ids)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  ids = line_ids or {}
end

---@param buf integer
---@param status string? what to say instead of the footer
local function redraw(buf, status)
  draw(buf, history:render(status))
end

--- The last line holding a task, or nil when none does.
---@return integer?
local function last_task_line()
  local last = nil
  for line in pairs(ids) do
    if not last or line > last then
      last = line
    end
  end

  return last
end

--- Read windows until one brings a task or the walk reaches its floor.
---
--- An account whose recent windows hold nothing costs several requests before
--- the first task appears, which is the price of a window the API caps at three
--- months. The buffer says it is reading the whole time rather than sitting
--- blank, so those requests do not read as a hang.
---@param buf integer
local function load(buf)
  if in_flight or not history or history:spent() then
    return
  end

  local walking = history
  local held = walking:len()
  in_flight = true

  -- `history` may have moved on to a newer walk by the time this fires, in
  -- which case that walk owns `in_flight` now and this stale answer must not
  -- clear it out from under it.
  local function stop()
    if history == walking then
      in_flight = false
    end
  end

  local function step()
    local request = walking:request()
    if not request then
      stop()
      return redraw(buf)
    end

    redraw(buf, "Reading completed tasks...")

    client.completed_page(request.since, request.until_, request.cursor, function(page, err)
      if history ~= walking or not vim.api.nvim_buf_is_valid(buf) then
        return stop()
      end

      if err then
        stop()
        -- The client has already raised the API's own message; this is the same
        -- message where the operator is looking.
        return redraw(buf, "The API refused this page: " .. err.message)
      end

      if type(page) ~= "table" or type(page.items) ~= "table" then
        stop()
        return redraw(buf, "The API answered without a page of completed tasks.")
      end

      walking:accept(page)

      if walking:len() > held or walking:spent() then
        stop()
        return redraw(buf)
      end

      step()
    end)
  end

  step()
end

--- Ask for the next page once the cursor has reached the last task on screen.
---
--- Wired to `CursorMoved`, so it covers `j`, `G`, a scroll and a mouse click
--- alike, and it asks for nothing until the cursor moves again.
function M.load_more()
  if not history or in_flight or history:spent() then
    return
  end

  local last = last_task_line()
  if not last or vim.api.nvim_win_get_cursor(0)[1] < last then
    return
  end

  load(vim.api.nvim_get_current_buf())
end

--- Reopen the task on the cursor's line.
---
--- It stops being completed, so on success its line leaves the buffer at once.
--- A refusal leaves every line where it is and reports the API's own wording,
--- which is what a task that was never completed answers with.
function M.reopen_under_cursor()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local id = ids[line]

  if not id then
    return vim.notify("todoist.nvim: no task on this line", vim.log.levels.WARN)
  end

  local buf = vim.api.nvim_get_current_buf()
  local walking = history

  client.reopen_task(id, function(_, err)
    if err or history ~= walking then
      return
    end

    walking:forget(id)
    redraw(buf)
    vim.notify("todoist.nvim: reopened that task", vim.log.levels.INFO)
  end)
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
  vim.bo[buf].filetype = "todoist-completed"

  -- The buffer is not modifiable, so `u` has no undo to do here.
  vim.keymap.set("n", "u", M.reopen_under_cursor, { buffer = buf, desc = "Todoist: reopen this task" })
  vim.keymap.set("n", "R", M.open, { buffer = buf, desc = "Todoist: read the history again from today" })

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    group = vim.api.nvim_create_augroup("todoist-completed", { clear = true }),
    desc = "Todoist: read the next page of completed tasks at the bottom of the list",
    callback = M.load_more,
  })

  return buf
end

--- Put the completed history in the current window, starting from today.
---
--- Returns while the first request is still out: the buffer appears at once
--- saying it is reading, and is redrawn as pages land.
---@return integer buf
function M.open()
  local buf = ensure_buffer()

  require("todoist.sidebar").leave_fixed_window()
  vim.api.nvim_win_set_buf(0, buf)

  history = completed_history.new()
  in_flight = false
  draw(buf, { "Todoist: completed", "", "Reading completed tasks..." })

  load(buf)

  return buf
end

return M
