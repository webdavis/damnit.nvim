local M = {}

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

local NOT_A_HOLE = false

local function record_line_roles_before_the_text(buf, kinds, oids, sections)
  vim.b[buf].damnit_kinds = kinds
  vim.b[buf].damnit_oids = oids
  vim.b[buf].damnit_sections = sections
end

local function clear_every_mark_including_virtual_lines(buf)
  vim.api.nvim_buf_clear_namespace(buf, M.NAMESPACE, 0, -1)
end

function M.draw(buf, lines)
  local text, kinds, oids, sections = {}, {}, {}, {}

  for index, line in ipairs(lines) do
    text[index] = line.text
    kinds[index] = line.kind
    oids[index] = line.oid or NOT_A_HOLE
    sections[index] = line.section or NOT_A_HOLE
  end

  record_line_roles_before_the_text(buf, kinds, oids, sections)
  clear_every_mark_including_virtual_lines(buf)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].modifiable = false

  M.mark(buf, lines, 0)
end

return M
