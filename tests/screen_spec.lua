local app = require("damnit").app()
local TESTS_DIR = require("helpers.paths").TESTS

local clock = require("helpers.clock")
local fake_process = require("helpers.fake_process")
local list_buffer = require("helpers.list_buffer")
local function queue()
  return require("damnit").app().queue
end
local screen = require("helpers.screen")
local sidebar = require("damnit.sidebar")
local sidebar_tab = require("helpers.sidebar_tab")
local status_window = require("helpers.status_window")

local TEN_AM_UTC_ON_THE_TWENTIETH = 1789898400

local EIGHT_OBJECTS = TESTS_DIR .. "/fixtures/long"

local function dam_list_in_a_window_that_wraps()
  vim.wo.wrap = true
  vim.cmd("Dam list")

  return vim.api.nvim_get_current_buf()
end

local function golden_rows(name)
  local file = assert(io.open(("%s/golden/screen/%s.txt"):format(TESTS_DIR, name), "r"))
  local rows = vim.split(file:read("*a"), "\n")
  file:close()

  return rows
end

return {
  ["the staging window on the full fixtures draws this screen at 80x24"] = function()
    clock.at(TEN_AM_UTC_ON_THE_TWENTIETH, function()
      status_window.with(function()
        screen.matches_golden("staging")
      end)
    end)
  end,

  ["a running call takes the help row and moves nothing else on the staging screen"] = function()
    clock.at(TEN_AM_UTC_ON_THE_TWENTIETH, function()
      status_window.with(function(fake)
        screen.fix_size()
        fake.hold = true
        queue().submit({ args = { "status", "--json" }, label = "push fake" })
        assert(
          vim.wait(2000, function()
            return vim.api.nvim_buf_get_lines(0, 2, 3, false)[1]:find("Running:", 1, true) ~= nil
          end, 50),
          "no tick wrote the running call into the header"
        )

        local got = vim.split((screen.dump():gsub("%d+%.%ds", "0.0s", 1)), "\n")
        local want = golden_rows("staging")
        want[15] = "Running: push fake  0.0s     [C-c to cancel]"
        assert(vim.deep_equal(got, want), "--- got ---\n" .. table.concat(got, "\n"))

        fake.release()
        fake_process.drain()
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
      sidebar_tab.wait_until_drawn_from_dams_answer(sidebar.toggle(app))
      screen.matches_golden("sidebar")
    end)
  end,

  ["the sidebar keeps its view beside :Dam list and then :Dam done in the main window"] = function()
    sidebar_tab.in_its_own_tabpage({}, function()
      screen.fix_size()
      sidebar_tab.wait_until_drawn_from_dams_answer(sidebar.toggle(app))
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
