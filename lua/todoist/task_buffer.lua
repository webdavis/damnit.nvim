-- One task as an editable buffer.
--
-- `buftype=acwrite` is what makes `:w` a callback instead of a file write, and
-- it is also what gives `:q` on an edited buffer Neovim's own unsaved-changes
-- path, so the operator gets the refusal or the prompt they get from any other
-- buffer rather than one invented here.
--
-- The write is the client's async request like every other, so a slow network
-- cannot stop the editor taking keystrokes. `modified` therefore stays set until
-- the API answers: the buffer says "unwritten" for exactly as long as it is,
-- and a rejected write leaves the operator's text where they can fix it.
--
-- This module works as the only thing in a fresh Neovim, entered straight onto
-- it with `nvim +"Todoist task <id>"`. It draws nothing but the buffer.

local M = {}

local client = require("todoist.client")
local format = require("todoist.task_format")

local GROUP = vim.api.nvim_create_augroup("todoist_task_buffer", { clear = true })

--- The task each buffer was last rendered from, keyed by buffer number. It is
--- what a write diffs against, so it is the API's own description of the task
--- rather than anything read back out of the text.
---@type table<integer, table>
local rendered = {}

---@param id string
---@return string
local function buffer_name(id)
  return "todoist://task/" .. id
end

--- `vim.fn.bufnr` matches by substring, which lets one task's id hijack
--- another's buffer when one id contains another. This matches the name
--- exactly.
---@param name string
---@return integer buf or -1
local function find_buffer(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == name then
      return buf
    end
  end
  return -1
end

--- Move out of a window that refuses a new buffer, so a task opened from the
--- sidebar lands in the work beside it rather than replacing the list.
local function leave_fixed_window()
  if not vim.wo.winfixbuf then
    return
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not vim.wo[win].winfixbuf then
      return vim.api.nvim_set_current_win(win)
    end
  end

  -- Nowhere to put it. The far-side split takes its columns from the tabpage
  -- rather than out of the fixed window.
  vim.cmd("botright vsplit")
end

---@param message string
---@param level integer?
local function notify(message, level)
  vim.notify("todoist.nvim: " .. message, level or vim.log.levels.INFO)
end

---@param buf integer
---@param task table
local function draw(buf, task)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, format.render(task))
  vim.bo[buf].modified = false

  rendered[buf] = task
end

--- Read the buffer, validate it, and send what changed.
---
--- A local refusal is reported and the buffer is left modified, because the text
--- the operator has to correct is the text that is in it. An API refusal is
--- reported by the client in the API's own wording, which is more use than
--- anything this plugin could say about a due string it does not parse.
---@param buf integer
function M.write(buf)
  local task = rendered[buf]
  if not task then
    return notify("this buffer is not holding a task any more", vim.log.levels.WARN)
  end

  local header, description, parse_err = format.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  if parse_err then
    return notify(parse_err, vim.log.levels.WARN)
  end

  local fields, invalid = format.changes(task, header, description)
  if invalid then
    return notify(invalid, vim.log.levels.WARN)
  end

  if vim.tbl_isempty(fields) then
    vim.bo[buf].modified = false
    return notify("nothing changed")
  end

  local sent = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  client.update_task(task.id, fields, function(updated, err)
    if err or not vim.api.nvim_buf_is_valid(buf) then
      -- The client has already raised the API's own message.
      return
    end

    if type(updated) == "table" and vim.deep_equal(sent, vim.api.nvim_buf_get_lines(buf, 0, -1, false)) then
      -- Redrawn from what the API recorded, so a due string it turned into a
      -- date shows up as the date it now holds.
      draw(buf, updated)
    else
      vim.bo[buf].modified = false
    end

    notify("saved " .. task.id)
  end)
end

--- Put one task in the current window as an editable buffer.
---@param task table as the API returned it
---@return integer buf
function M.show(task)
  local name = buffer_name(task.id)
  local buf = find_buffer(name)

  if buf == -1 then
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, name)

    vim.bo[buf].buftype = "acwrite"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "markdown"

    -- Registered once per buffer: a second `show` on the same buffer would
    -- otherwise add a second `BufWriteCmd`, and `:w` would fire every one.
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      group = GROUP,
      buffer = buf,
      desc = "write one Todoist task back",
      callback = function()
        M.write(buf)
      end,
    })

    vim.api.nvim_create_autocmd("BufWipeout", {
      group = GROUP,
      buffer = buf,
      desc = "forget the task a wiped buffer held",
      callback = function()
        rendered[buf] = nil
      end,
    })
  end

  leave_fixed_window()
  vim.api.nvim_win_set_buf(0, buf)

  -- A modified buffer holds text the operator has not saved; reopening the
  -- same task must not throw it away.
  if not vim.bo[buf].modified then
    draw(buf, task)
  end

  return buf
end

--- Fetch one task and open it. Returns while the request is still out; the
--- buffer appears when it answers, and a failure is the client's notification.
---@param id string
function M.open(id)
  client.get_task(id, function(task, err)
    if err then
      return
    end

    if type(task) ~= "table" or not task.id then
      return notify("the API answered without a task", vim.log.levels.WARN)
    end

    M.show(task)
  end)
end

return M
