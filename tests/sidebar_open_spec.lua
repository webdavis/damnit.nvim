local TESTS_DIR = arg[0]:match("(.*)/") or "."

local sidebar_tab = dofile(TESTS_DIR .. "/helpers/sidebar_tab.lua")
local list = require("damnit.list")
local location_edit = require("damnit.location_edit")
local sidebar = require("damnit.sidebar")

return {
  ["another buffer cannot be opened into the sidebar"] = function()
    sidebar_tab.in_its_own_tabpage({}, function()
      local win = sidebar.toggle()
      sidebar_tab.wait_until_drawn_from_dams_answer(win)
      local held = vim.api.nvim_win_get_buf(win)

      local ok = pcall(vim.api.nvim_win_set_buf, win, vim.api.nvim_create_buf(false, true))

      assert(not ok, "a foreign buffer was accepted")
      assert(vim.api.nvim_win_get_buf(win) == held, "the sidebar lost its list")
    end)
  end,

  ["opening an object from the sidebar lands beside it, not inside it"] = function()
    sidebar_tab.in_its_own_tabpage({}, function()
      local win = sidebar.toggle()
      sidebar_tab.wait_until_drawn_from_dams_answer(win)
      local held = vim.api.nvim_win_get_buf(win)

      sidebar_tab.cursor_to(win, "buy oat milk")
      vim.api.nvim_set_current_win(win)
      list.open_under_cursor()

      assert(vim.api.nvim_get_current_win() ~= win, "the object opened into the sidebar")
      assert(sidebar.window() == win, "the sidebar window is gone")
      assert(vim.api.nvim_win_get_buf(win) == held, "the sidebar lost its list")
    end)
  end,

  ["opening an object with the sidebar alone in the tabpage splits rather than erroring"] = function()
    sidebar_tab.in_its_own_tabpage({}, function()
      local win = sidebar.toggle()
      sidebar_tab.wait_until_drawn_from_dams_answer(win)

      sidebar_tab.cursor_to(win, "buy oat milk")
      vim.api.nvim_set_current_win(win)
      vim.cmd("only")

      local before = sidebar_tab.windows_in_this_tabpage()
      local ok, err = pcall(list.open_under_cursor)

      assert(ok, "opening an object with the sidebar alone raised: " .. tostring(err))
      assert(
        sidebar_tab.windows_in_this_tabpage() == before + 1,
        "no split was made for the object: " .. sidebar_tab.windows_in_this_tabpage()
      )
      assert(sidebar.window() == win, "the sidebar window is gone")
    end)
  end,

  ["gd from the sidebar opens the file beside it"] = function()
    sidebar_tab.in_its_own_tabpage({}, function()
      local root = vim.fs.normalize(vim.fn.tempname())
      vim.fn.mkdir(root .. "/lua", "p")
      local handle = assert(io.open(root .. "/lua/list.lua", "w"))
      handle:write("one\ntwo\nthree\n")
      handle:close()

      local win = sidebar.toggle()
      sidebar_tab.wait_until_drawn_from_dams_answer(win)
      local held = vim.api.nvim_win_get_buf(win)

      sidebar_tab.cursor_to(win, "hold the sidebar width")
      vim.api.nvim_set_current_win(win)
      vim.cmd.tcd(vim.fn.fnameescape(root))

      local the_fixture_location_rewritten_for_this_tabpage_directory = { path = "lua/list.lua", line = 2 }
      local jumped = location_edit.jump(the_fixture_location_rewritten_for_this_tabpage_directory)

      assert(jumped, "the jump was refused")
      assert(vim.api.nvim_get_current_win() ~= win, "the file opened into the sidebar")
      assert(vim.api.nvim_win_get_buf(win) == held, "the sidebar lost its list")
      assert(vim.endswith(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), "/lua/list.lua"), "the wrong file opened")
    end)
  end,
}
