-- One object as a buffer.
--
-- The buffer stays modified until dam answers, so an edit that has not landed
-- still reads as unwritten and a refused one leaves the text where it can be
-- fixed.

local M = {}

local message = require("damnit.message")
local task_format = require("damnit.task_format")

--- Its own namespace: `damnit.render` already clears the whole `damnit` one in
--- the buffer it draws.
M.NAMESPACE = vim.api.nvim_create_namespace("damnit.diagnostics")

--- The object each buffer was last drawn from, which is what a write diffs
--- against.
---@type table<integer, table>
local objects = {}

---@param buf integer
---@param text string
---@param line integer
local function diagnose(buf, text, line)
  vim.diagnostic.set(M.NAMESPACE, buf, {
    {
      lnum = math.max(line - 1, 0),
      col = 0,
      severity = vim.diagnostic.severity.ERROR,
      source = "damnit",
      message = text,
    },
  })
end

--- Draw one object and remember it, so the next write knows what changed.
---@param object table
---@param buf integer?
---@return integer buf
function M.show(object, buf)
  buf = buf or vim.api.nvim_get_current_buf()

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, task_format.render(object))
  vim.bo[buf].modified = false

  objects[buf] = object
  vim.diagnostic.reset(M.NAMESPACE, buf)

  return buf
end

--- Queue one call that ends with the object dam answered with, or with dam's
--- refusal as a diagnostic on line one.
---@param buf integer
---@param args string[]
---@param label string
local function send(buf, args, label)
  require("damnit.queue").submit({
    args = args,
    label = label,
    on_done = function(updated, failure)
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end

      if failure then
        return diagnose(buf, failure.message, 1)
      end

      M.show(updated, buf)
    end,
  })
end

--- Send what the buffer changed: one `dam edit`, and `dam mv` when the path did.
---@param buf integer
function M.write(buf)
  local object = objects[buf]
  if not object then
    return message.warn("this buffer has no object to write")
  end

  vim.diagnostic.reset(M.NAMESPACE, buf)

  local header, body, err = task_format.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  if err then
    return diagnose(buf, err, 1)
  end

  local changes, refused = task_format.changes(object, header, body)
  if refused then
    return diagnose(buf, refused.message, refused.line)
  end

  if #changes.edit == 0 and not changes.move then
    vim.bo[buf].modified = false

    return message.warn("nothing changed")
  end

  if #changes.edit > 0 then
    local args = { "edit", object.oid }
    vim.list_extend(args, changes.edit)
    args[#args + 1] = "--json"

    send(buf, args, "edit")
  end

  if changes.move then
    send(buf, { "mv", object.oid, changes.move, "--json" }, "mv")
  end
end

--- Open one object by oid in the current window.
---@param oid string
---@return integer buf
function M.open(oid)
  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_name(buf, ("damnit://task/%s"):format(oid))
  vim.bo[buf].filetype = "damtask"
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].swapfile = false

  -- The sidebar refuses a foreign buffer, so an object opened from it lands in
  -- the work beside it rather than failing.
  require("damnit.sidebar").leave_fixed_window()
  vim.api.nvim_win_set_buf(0, buf)

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    desc = "dam: write this object back",
    callback = function()
      M.write(buf)
    end,
  })

  require("damnit.queue").submit({
    args = { "show", oid, "--json" },
    label = "show",
    on_done = function(object, err)
      if err then
        return message.report(err)
      end

      if vim.api.nvim_buf_is_valid(buf) then
        M.show(object, buf)
      end
    end,
  })

  return buf
end

return M
