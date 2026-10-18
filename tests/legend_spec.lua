local TESTS_DIR = arg[0]:match("(.*)/") or "."

local keys = require("damnit.keys")
local list_buffer = dofile(TESTS_DIR .. "/helpers/list_buffer.lua")
local render = require("damnit.render")
local status_window = dofile(TESTS_DIR .. "/helpers/status_window.lua")

local STAGING_LEGEND = "g? help  - stage  cc commit  P push  p pull  R re-read"
local LIST_LEGEND = "g? help  <CR> open  x done  p priority  s due  a add"

local function winbar_of(win)
  return vim.api.nvim_eval_statusline(vim.wo[win].winbar, { winid = win, use_winbar = true, highlights = true })
end

return {
  ["the staging legend names the six most-used keys from the key table"] = function()
    assert(keys.legend("damstatus") == STAGING_LEGEND, keys.legend("damstatus"))
  end,

  ["the list legend names the six most-used keys from the key table"] = function()
    assert(keys.legend("damlist") == LIST_LEGEND, keys.legend("damlist"))
  end,

  ["a narrow legend drops whole entries from the end rather than cutting one"] = function()
    assert(keys.legend("damlist", 26) == "g? help  <CR> open  x done", keys.legend("damlist", 26))
    assert(keys.legend("damlist", 25) == "g? help  <CR> open", keys.legend("damlist", 25))
    assert(keys.legend("damlist", 3) == "", keys.legend("damlist", 3))
  end,

  ["the staging window's third row is the legend, drawn faint"] = function()
    status_window.with(function()
      local buf = vim.api.nvim_get_current_buf()
      assert(vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1] == STAGING_LEGEND)

      local marks = vim.api.nvim_buf_get_extmarks(buf, render.NAMESPACE, { 2, 0 }, { 2, -1 }, { details = true })
      assert(#marks == 1 and marks[1][4].hl_group == "DamLegend", vim.inspect(marks))
      assert(vim.api.nvim_get_hl(0, { name = "DamLegend", link = true }).link == "Comment")
    end)
  end,

  ["a list window carries the legend faint in its winbar, cut to the window's width"] = function()
    list_buffer.with(function()
      local win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_width(win, vim.o.columns)
      local bar = winbar_of(win)
      assert(bar.str:gsub("%s+$", "") == LIST_LEGEND, bar.str)
      assert(bar.highlights[1].group == "DamLegend", vim.inspect(bar.highlights))

      vim.cmd("vsplit")
      vim.api.nvim_win_set_width(win, 30)
      assert(winbar_of(win).str:gsub("%s+$", "") == "g? help  <CR> open  x done", winbar_of(win).str)
    end)
  end,
}
