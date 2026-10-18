local M = {}

local state_by_buf = {}

local drawn_by_buf = {}

function M.named(name, configure)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == name then
      return buf, false
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  state_by_buf[buf] = {}

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      state_by_buf[buf] = nil
    end,
  })

  configure(buf)

  return buf, true
end

function M.state(buf)
  return state_by_buf[buf]
end

local function unlisted_and_gone_when_hidden(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
end

function M.read_only(name, lines, split)
  local buf = M.named(name, unlisted_and_gone_when_hidden)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  if not M.focus(buf) then
    vim.cmd(split)
    vim.api.nvim_win_set_buf(0, buf)
  end

  return buf
end

function M.focus(buf)
  local win = vim.fn.bufwinid(buf)

  if win == -1 then
    return false
  end

  vim.api.nvim_set_current_win(win)

  return true
end

local function forget_the_rows_when_wiped(buf)
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      drawn_by_buf[buf] = nil
    end,
  })
end

function M.draw(buf, rows)
  local text = {}
  for index, row in ipairs(rows) do
    text[index] = row.text
  end

  if not drawn_by_buf[buf] then
    forget_the_rows_when_wiped(buf)
  end
  drawn_by_buf[buf] = rows

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].modifiable = false
end

function M.rows(buf)
  return drawn_by_buf[buf] or {}
end

function M.row(buf, lnum)
  return M.rows(buf)[lnum]
end

return M
