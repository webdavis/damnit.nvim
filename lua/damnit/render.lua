local M = {}

local scratch = require("damnit.scratch")

M.NAMESPACE = vim.api.nvim_create_namespace("damnit")

function M.mark(buf, lines, from)
  vim.api.nvim_buf_clear_namespace(buf, M.NAMESPACE, from, from + #lines)

  for index, line in ipairs(lines) do
    for _, mark in ipairs(line.marks) do
      vim.api.nvim_buf_set_extmark(buf, M.NAMESPACE, from + index - 1, mark.col, {
        end_col = mark.col + mark.length,
        hl_group = mark.group,
      })
    end
  end
end

local function clear_every_mark_including_virtual_lines(buf)
  vim.api.nvim_buf_clear_namespace(buf, M.NAMESPACE, 0, -1)
end

function M.draw(buf, lines)
  clear_every_mark_including_virtual_lines(buf)
  scratch.draw(buf, lines)
  M.mark(buf, lines, 0)
end

return M
