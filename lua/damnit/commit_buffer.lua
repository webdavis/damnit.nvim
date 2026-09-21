-- The commit message buffer and its write.
--
-- Written to commit rather than quit to commit: `dam commit -m` takes the
-- message as an argument, so this buffer is the plugin's own editing surface
-- rather than a file dam asked for.

local M = {}

local message = require("damnit.message")

--- The message a buffer's lines hold: everything that is not a comment line.
---@param lines string[]
---@return string
function M.message(lines)
  local kept = {}

  for _, line in ipairs(lines) do
    if not vim.startswith(line, "#") then
      kept[#kept + 1] = line
    end
  end

  return vim.trim(table.concat(kept, "\n"))
end

--- Send what the buffer holds, or say why nothing was sent.
---@param buf integer
function M.write(buf)
  local text = M.message(vim.api.nvim_buf_get_lines(buf, 0, -1, false))

  if text == "" then
    return message.warn("no commit message; the commit was not made")
  end

  require("damnit.queue").submit({
    args = { "commit", "-m", text, "--json" },
    label = "commit",
    on_done = function(report, err)
      if err then
        return message.report(err)
      end

      message.say(("%s committed, %d changes"):format(tostring(report.id):sub(1, 7), #(report.changes or {})))

      vim.bo[buf].modified = false
      vim.api.nvim_buf_delete(buf, { force = true })
      require("damnit.window").refresh()
    end,
  })
end

--- The staged section of the status the window last drew.
---@param key string?
---@return damnit.Section?
local function staged(key)
  local model = require("damnit.window").model(key)

  for _, section in ipairs((model or {}).sections or {}) do
    if section.kind == "staged" then
      return section
    end
  end

  return nil
end

--- Open the message buffer for what is staged, or say nothing is.
---@param key string?
---@return integer? buf
function M.open(key)
  local section = staged(key)

  if not section then
    message.warn("nothing is staged to commit")

    return nil
  end

  local lines = { "", "# Staged" }
  for _, entry in ipairs(section.entries) do
    lines[#lines + 1] = ("# %-8s %s  %s"):format(entry.verb, entry.oid:sub(1, 7), entry.subject)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, ("damnit://commit/%s"):format(key or require("damnit.queue").key()))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "damcommitmsg"
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    desc = "dam: commit what this buffer says",
    callback = function()
      M.write(buf)
    end,
  })

  vim.cmd("split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd("startinsert")

  return buf
end

return M
