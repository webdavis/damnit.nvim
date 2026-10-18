local M = {}

local render = require("damnit.render")
local store = require("damnit.store")

function M.state(app, key, win)
  return {
    store = store.display(key),
    running = app.queue.foreground(key),
    now = os.time(),
    width = win and vim.api.nvim_win_get_width(win) or nil,
  }
end

function M.rewrite(buf, lines)
  local head, text = {}, {}
  for index, line in ipairs(lines) do
    if line.kind ~= "header" then
      break
    end
    head[index], text[index] = line, line.text
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, #head, false, text)
  vim.bo[buf].modifiable = false

  render.mark(buf, head, 0)
end

return M
