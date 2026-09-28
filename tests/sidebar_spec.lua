local TESTS_DIR = arg[0]:match("(.*)/") or "."

local sidebar_tab = dofile(TESTS_DIR .. "/helpers/sidebar_tab.lua")
local sidebar = require("damnit.sidebar")
local views = require("damnit.views")

local function refuse_the_name_as_the_list_does_once_dam_answers_parse(name)
  views.forget_filter(name)
end

return {
  ["toggle opens a fixed-width split and a second call closes it"] = function()
    sidebar_tab.in_its_own_tabpage({}, function()
      local before = sidebar_tab.windows_in_this_tabpage()

      local win = sidebar.toggle()
      assert(win, "toggle opened nothing")
      assert(sidebar_tab.windows_in_this_tabpage() == before + 1, "windows: " .. sidebar_tab.windows_in_this_tabpage())
      assert(vim.api.nvim_win_get_width(win) == sidebar_tab.CONFIGURED_WIDTH, vim.api.nvim_win_get_width(win))
      sidebar_tab.wait_until_drawn_from_dams_answer(win)

      sidebar.toggle()
      assert(
        sidebar_tab.windows_in_this_tabpage() == before,
        "windows after the second toggle: " .. sidebar_tab.windows_in_this_tabpage()
      )
      assert(not sidebar.window(), "a sidebar window is still marked")
    end)
  end,

  ["the width survives another window opening and an equalizing command"] = function()
    sidebar_tab.in_its_own_tabpage({}, function()
      local win = sidebar.toggle()
      sidebar_tab.wait_until_drawn_from_dams_answer(win)

      vim.cmd("vsplit")
      assert(
        vim.api.nvim_win_get_width(win) == sidebar_tab.CONFIGURED_WIDTH,
        "after vsplit: " .. vim.api.nvim_win_get_width(win)
      )

      vim.cmd("split")
      assert(
        vim.api.nvim_win_get_width(win) == sidebar_tab.CONFIGURED_WIDTH,
        "after split: " .. vim.api.nvim_win_get_width(win)
      )

      vim.cmd("wincmd =")
      assert(
        vim.api.nvim_win_get_width(win) == sidebar_tab.CONFIGURED_WIDTH,
        "after wincmd =: " .. vim.api.nvim_win_get_width(win)
      )

      vim.cmd("wincmd p")
      vim.cmd("close")
      assert(
        vim.api.nvim_win_get_width(win) == sidebar_tab.CONFIGURED_WIDTH,
        "after a close: " .. vim.api.nvim_win_get_width(win)
      )
    end)
  end,

  ["the width comes back once the only window in the tabpage has company"] = function()
    sidebar_tab.in_its_own_tabpage({}, function()
      local win = sidebar.toggle()
      sidebar_tab.wait_until_drawn_from_dams_answer(win)

      vim.api.nvim_set_current_win(win)
      vim.cmd("only")
      vim.cmd("vsplit")

      assert(
        vim.api.nvim_win_get_width(win) == sidebar_tab.CONFIGURED_WIDTH,
        "after standing alone: " .. vim.api.nvim_win_get_width(win)
      )
    end)
  end,

  ["the side comes from config"] = function()
    sidebar_tab.in_its_own_tabpage({ side = "left" }, function()
      local win = sidebar.toggle()
      sidebar_tab.wait_until_drawn_from_dams_answer(win)
      assert(vim.api.nvim_win_get_position(win)[2] == 0, "a left sidebar is not at column 0")
    end)

    sidebar_tab.in_its_own_tabpage({ side = "right" }, function()
      local win = sidebar.toggle()
      sidebar_tab.wait_until_drawn_from_dams_answer(win)
      local column = vim.api.nvim_win_get_position(win)[2]
      assert(column + vim.api.nvim_win_get_width(win) >= vim.o.columns - 1, "a right sidebar is not at the far edge")
    end)
  end,

  ["a side it cannot read leaves the layout alone"] = function()
    local _, notifications = sidebar_tab.in_its_own_tabpage({ side = "up" }, function()
      local before = sidebar_tab.windows_in_this_tabpage()
      sidebar.toggle()
      assert(sidebar_tab.windows_in_this_tabpage() == before, "the layout changed")
    end)

    assert(#notifications == 1, vim.inspect(notifications))
    assert(notifications[1]:find("sidebar.side", 1, true), notifications[1])
  end,

  ["a width that is not a count of columns leaves the layout alone"] = function()
    local _, notifications = sidebar_tab.in_its_own_tabpage({ width = 0 }, function()
      local before = sidebar_tab.windows_in_this_tabpage()
      sidebar.toggle()
      assert(sidebar_tab.windows_in_this_tabpage() == before, "the layout changed")
    end)

    assert(#notifications == 1, vim.inspect(notifications))
    assert(notifications[1]:find("sidebar.width", 1, true), notifications[1])
  end,

  ["a view dam has already refused leaves the layout alone"] = function()
    local _, notifications = sidebar_tab.in_its_own_tabpage({ view = "tomorrow" }, function()
      refuse_the_name_as_the_list_does_once_dam_answers_parse("tomorrow")

      local before = sidebar_tab.windows_in_this_tabpage()
      sidebar.toggle()
      assert(sidebar_tab.windows_in_this_tabpage() == before, "the layout changed")
    end)

    assert(#notifications == 1, vim.inspect(notifications))
    assert(notifications[1]:find('no view named "tomorrow"', 1, true), notifications[1])
  end,

  ["a sidebar closed with :q leaves no idea of an open one behind"] = function()
    sidebar_tab.in_its_own_tabpage({}, function()
      local win = sidebar.toggle()
      sidebar_tab.wait_until_drawn_from_dams_answer(win)

      vim.api.nvim_set_current_win(win)
      vim.cmd("quit")

      assert(not sidebar.window(), "the closed window is still the sidebar")

      local reopened = sidebar.toggle()
      assert(reopened and reopened ~= win, "toggle did not open a new sidebar")
      assert(vim.api.nvim_win_get_width(reopened) == sidebar_tab.CONFIGURED_WIDTH, vim.api.nvim_win_get_width(reopened))
    end)
  end,

  ["it says it is loading while the first fetch is out"] = function()
    sidebar_tab.in_its_own_tabpage({ slow_first_fetch = true }, function()
      local win = sidebar.toggle()
      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)

      assert(lines[1]:find("today", 1, true), vim.inspect(lines))
      assert(vim.tbl_contains(lines, "Loading..."), vim.inspect(lines))
    end)
  end,

  ["toggle in another tabpage opens one there rather than closing the first"] = function()
    sidebar_tab.in_its_own_tabpage({}, function()
      local first = sidebar.toggle()
      sidebar_tab.wait_until_drawn_from_dams_answer(first)

      vim.cmd("tabnew")
      local second = sidebar.toggle()

      assert(second and second ~= first, "the second tabpage got no sidebar of its own")
      assert(vim.api.nvim_win_is_valid(first), "the first tabpage's sidebar was closed")
    end)
  end,
}
