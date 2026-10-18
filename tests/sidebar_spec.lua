local with_dam = require("helpers.harness").with_dam
local app = require("damnit").app()

local sidebar_tab = require("helpers.sidebar_tab")
local sidebar = require("damnit.sidebar")
local fake_process = require("helpers.fake_process")
local function queue()
  return require("damnit").app().queue
end

return {
  ["toggle opens a fixed-width split and a second call closes it"] = function()
    with_dam(sidebar_tab.opts({}), function()
      local before = sidebar_tab.windows_in_this_tabpage()

      local win = sidebar.toggle(app)
      assert(win, "toggle opened nothing")
      assert(sidebar_tab.windows_in_this_tabpage() == before + 1, "windows: " .. sidebar_tab.windows_in_this_tabpage())
      assert(vim.api.nvim_win_get_width(win) == sidebar_tab.CONFIGURED_WIDTH, vim.api.nvim_win_get_width(win))
      sidebar_tab.wait_until_drawn_from_dams_answer(win)

      sidebar.toggle(app)
      assert(
        sidebar_tab.windows_in_this_tabpage() == before,
        "windows after the second toggle: " .. sidebar_tab.windows_in_this_tabpage()
      )
      assert(not sidebar.window(), "a sidebar window is still marked")
    end)
  end,

  ["the width survives another window opening and an equalizing command"] = function()
    with_dam(sidebar_tab.opts({}), function()
      local win = sidebar.toggle(app)
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
    with_dam(sidebar_tab.opts({}), function()
      local win = sidebar.toggle(app)
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
    with_dam(sidebar_tab.opts({ side = "left" }), function()
      local win = sidebar.toggle(app)
      sidebar_tab.wait_until_drawn_from_dams_answer(win)
      assert(vim.api.nvim_win_get_position(win)[2] == 0, "a left sidebar is not at column 0")
    end)

    with_dam(sidebar_tab.opts({ side = "right" }), function()
      local win = sidebar.toggle(app)
      sidebar_tab.wait_until_drawn_from_dams_answer(win)
      local column = vim.api.nvim_win_get_position(win)[2]
      assert(column + vim.api.nvim_win_get_width(win) >= vim.o.columns - 1, "a right sidebar is not at the far edge")
    end)
  end,

  ["a side it cannot read leaves the layout alone"] = function()
    local notifications = with_dam(sidebar_tab.opts({ side = "up" }), function()
      local before = sidebar_tab.windows_in_this_tabpage()
      sidebar.toggle(app)
      assert(sidebar_tab.windows_in_this_tabpage() == before, "the layout changed")
    end).said

    assert(#notifications == 1, vim.inspect(notifications))
    assert(notifications[1]:find("sidebar.side", 1, true), notifications[1])
  end,

  ["a width that is not a count of columns leaves the layout alone"] = function()
    local notifications = with_dam(sidebar_tab.opts({ width = 0 }), function()
      local before = sidebar_tab.windows_in_this_tabpage()
      sidebar.toggle(app)
      assert(sidebar_tab.windows_in_this_tabpage() == before, "the layout changed")
    end).said

    assert(#notifications == 1, vim.inspect(notifications))
    assert(notifications[1]:find("sidebar.width", 1, true), notifications[1])
  end,

  ["a view in neither the setup nor dam's saved filters leaves the layout alone"] = function()
    local notifications = with_dam(sidebar_tab.opts({ view = "tomorrow" }), function()
      local before = sidebar_tab.windows_in_this_tabpage()
      sidebar.toggle(app)
      fake_process.settle(function()
        return queue().running() == nil
      end)

      assert(sidebar_tab.windows_in_this_tabpage() == before, "the layout changed")
    end).said

    assert(#notifications == 1, vim.inspect(notifications))
    assert(notifications[1]:find('no view named "tomorrow"', 1, true), notifications[1])
  end,

  ["a sidebar closed with :q leaves no idea of an open one behind"] = function()
    with_dam(sidebar_tab.opts({}), function()
      local win = sidebar.toggle(app)
      sidebar_tab.wait_until_drawn_from_dams_answer(win)

      vim.api.nvim_set_current_win(win)
      vim.cmd("quit")

      assert(not sidebar.window(), "the closed window is still the sidebar")

      local reopened = sidebar.toggle(app)
      assert(reopened and reopened ~= win, "toggle did not open a new sidebar")
      assert(vim.api.nvim_win_get_width(reopened) == sidebar_tab.CONFIGURED_WIDTH, vim.api.nvim_win_get_width(reopened))
    end)
  end,

  ["it says it is loading while the first fetch is out"] = function()
    with_dam(sidebar_tab.opts({}), function()
      local win = sidebar.toggle(app)
      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)

      assert(lines[1]:find("today", 1, true), vim.inspect(lines))
      assert(vim.tbl_contains(lines, "Loading..."), vim.inspect(lines))
    end)
  end,

  ["toggle in another tabpage opens one there rather than closing the first"] = function()
    with_dam(sidebar_tab.opts({}), function()
      local first = sidebar.toggle(app)
      sidebar_tab.wait_until_drawn_from_dams_answer(first)

      vim.cmd("tabnew")
      local second = sidebar.toggle(app)

      assert(second and second ~= first, "the second tabpage got no sidebar of its own")
      assert(vim.api.nvim_win_is_valid(first), "the first tabpage's sidebar was closed")
    end)
  end,
}
