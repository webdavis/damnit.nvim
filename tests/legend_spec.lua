local TESTS_DIR = arg[0]:match("(.*)/") or "."

local keymaps = require("damnit.keymaps")
local list_buffer = dofile(TESTS_DIR .. "/helpers/list_buffer.lua")
local render = require("damnit.render")
local status_window = dofile(TESTS_DIR .. "/helpers/status_window.lua")

local STAGING_LEGEND = "g? help  - stage  cc commit  P push  p pull  R re-read"
local LIST_LEGEND = "g? help  <CR> open  x done  p priority  s due  a add"

local function winbar_of(win)
  return vim.api.nvim_eval_statusline(vim.wo[win].winbar, { winid = win, use_winbar = true, highlights = true })
end

local function the_help_float_closes_on(key)
  list_buffer.with(function()
    vim.api.nvim_feedkeys("g?", "x", false)
    local float = vim.api.nvim_get_current_win()
    assert(vim.api.nvim_win_get_config(float).relative == "editor", "g? opened no float")

    vim.api.nvim_feedkeys(vim.keycode(key), "x", false)
    assert(not vim.api.nvim_win_is_valid(float), key .. " left the help float open")
  end)
end

return {
  ["q closes the help float"] = function()
    the_help_float_closes_on("q")
  end,

  ["g? closes the help float it opened"] = function()
    the_help_float_closes_on("g?")
  end,

  ["<Esc> closes the help float"] = function()
    the_help_float_closes_on("<Esc>")
  end,

  ["the staging legend names the six most-used keys from the key table"] = function()
    assert(keymaps.legend("damstatus") == STAGING_LEGEND, keymaps.legend("damstatus"))
  end,

  ["the list legend names the six most-used keys from the key table"] = function()
    assert(keymaps.legend("damlist") == LIST_LEGEND, keymaps.legend("damlist"))
  end,

  ["a narrow legend drops whole entries from the end rather than cutting one"] = function()
    assert(keymaps.legend("damlist", 26) == "g? help  <CR> open  x done", keymaps.legend("damlist", 26))
    assert(keymaps.legend("damlist", 25) == "g? help  <CR> open", keymaps.legend("damlist", 25))
    assert(keymaps.legend("damlist", 3) == "", keymaps.legend("damlist", 3))
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

  ["a 50-column staging window drops whole legend entries and cuts none"] = function()
    status_window.with(function()
      local win = vim.api.nvim_get_current_win()
      vim.cmd("vnew")
      vim.api.nvim_win_set_width(win, 50)
      vim.api.nvim_set_current_win(win)
      vim.api.nvim_exec_autocmds("WinResized", {})

      local row = vim.api.nvim_buf_get_lines(0, 2, 3, false)[1]
      assert(row == "g? help  - stage  cc commit  P push  p pull", row)
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
