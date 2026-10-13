local M = {}

local state_by_buf = {}

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

return M
