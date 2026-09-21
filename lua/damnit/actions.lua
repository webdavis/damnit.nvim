-- What each key does: read the cursor, queue the call, handle the result.

local M = {}

local message = require("damnit.message")

--- Re-read the status. Queued like anything else, so it waits behind a push.
function M.refresh()
  require("damnit.window").refresh()
end

function M.cancel()
  require("damnit.queue").cancel()
end

function M.close()
  vim.api.nvim_win_close(0, false)
end

--- Move to the count-th entry of a section, or say the section is not there.
---@param kind string
---@param heading string
---@param count integer
function M.jump_to_section(kind, heading, count)
  local line = require("damnit.window").line_of(kind, count)

  if not line then
    return message.warn(("no %s section"):format(heading))
  end

  vim.api.nvim_win_set_cursor(0, { line, 0 })
end

--- The key table for one filetype, in a float that closes on any key.
---@param filetype string
function M.help(filetype)
  local rows = {}
  for _, map in ipairs(require("damnit.keys").MAPS[filetype] or {}) do
    rows[#rows + 1] = ("  %-8s %s"):format(map[2], map[4])
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rows)
  vim.bo[buf].modifiable = false

  local width = 0
  for _, row in ipairs(rows) do
    width = math.max(width, #row)
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - #rows) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width + 2,
    height = #rows,
    style = "minimal",
    border = "rounded",
  })

  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once = true,
    callback = function()
      pcall(vim.api.nvim_win_close, win, true)
    end,
  })
end

return M
