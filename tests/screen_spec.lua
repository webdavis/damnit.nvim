local TESTS_DIR = arg[0]:match("(.*)/") or "."

local list_buffer = dofile(TESTS_DIR .. "/helpers/list_buffer.lua")
local screen = dofile(TESTS_DIR .. "/helpers/screen.lua")
local sidebar = require("damnit.sidebar")
local sidebar_tab = dofile(TESTS_DIR .. "/helpers/sidebar_tab.lua")
local status_window = dofile(TESTS_DIR .. "/helpers/status_window.lua")

local TEN_AM_UTC_ON_THE_TWENTIETH = 1789898400

local EIGHT_OBJECTS = TESTS_DIR .. "/fixtures/long"

local function dam_list_in_a_window_that_wraps()
  vim.wo.wrap = true
  vim.cmd("Dam list")

  return vim.api.nvim_get_current_buf()
end

local function with_the_clock_at(epoch, body)
  local real = os.time
  rawset(os, "time", function(date)
    return date and real(date) or epoch
  end)

  local ok, err = pcall(body)
  rawset(os, "time", real)

  assert(ok, err)
end

return {
  ["the staging window on the full fixtures draws this screen at 80x24"] = function()
    with_the_clock_at(TEN_AM_UTC_ON_THE_TWENTIETH, function()
      status_window.with(function()
        screen.matches_golden("staging")
      end)
    end)
  end,

  [":Dam list in a plain window draws this screen at 80x24"] = function()
    list_buffer.with(function()
      screen.matches_golden("list")
    end, {
      open = function()
        vim.cmd("Dam list")
        return vim.api.nvim_get_current_buf()
      end,
    })
  end,

  [":Dam list at 80 columns cuts a long row at the edge and bars the current row"] = function()
    list_buffer.with(function()
      screen.matches_golden("list_long")
      assert(vim.wo.cursorline, "the current row carries no bar")
      assert(not vim.wo.wrap, "the list wraps")
    end, { fixtures = EIGHT_OBJECTS, open = dam_list_in_a_window_that_wraps })
  end,

  ["the sidebar open on a view draws this screen at 80x24"] = function()
    sidebar_tab.in_its_own_tabpage({}, function()
      screen.fix_size()
      sidebar_tab.wait_until_drawn_from_dams_answer(sidebar.toggle())
      screen.matches_golden("sidebar")
    end)
  end,

  ["the sidebar keeps its view beside :Dam list and then :Dam done in the main window"] = function()
    sidebar_tab.in_its_own_tabpage({}, function()
      screen.fix_size()
      sidebar_tab.wait_until_drawn_from_dams_answer(sidebar.toggle())
      vim.cmd("wincmd p")

      vim.cmd("Dam list")
      sidebar_tab.wait_until_drawn_from_dams_answer(0)
      screen.matches_golden("sidebar_beside_list")

      vim.cmd("Dam done")
      sidebar_tab.wait_until_drawn_from_dams_answer(0)
      screen.matches_golden("sidebar_beside_done")
    end)
  end,
}
