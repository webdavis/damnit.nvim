local M = {}

function M.split_full_height_at(side)
  vim.cmd(side == "right" and "botright vsplit" or "topleft vsplit")
end

function M.leave()
  if not vim.wo.winfixbuf then
    return
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not vim.wo[win].winfixbuf then
      return vim.api.nvim_set_current_win(win)
    end
  end

  M.split_full_height_at("right")
end

return M
