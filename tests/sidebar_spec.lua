-- The sidebar: a fixed-width split holding one view.
--
-- Every case runs in a tabpage of its own against a fake dam, so one case's
-- layout is never another case's starting point and nothing reaches a store.

local TESTS_DIR = arg[0]:match("(.*)/") or "."

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local damnit = require("damnit")
local list = require("damnit.list")
local location_edit = require("damnit.location_edit")
local queue = require("damnit.queue")
local sidebar = require("damnit.sidebar")
local views = require("damnit.views")

local WIDTH = 34

--- Run `body` in its own tabpage, with the sidebar configured and a fake dam at
--- the front of PATH. `answer` false installs a fake that never answers, which
--- is what a slow first fetch looks like.
---@param opts { side: string?, width: integer?, view: string?, views: table?, answer: boolean? }
---@param body fun(fake: damnit.FakeDam): any
---@return any result
---@return string[] notifications
local function in_tab(opts, body)
  local options = damnit.options
  local real_notify = vim.notify
  local columns = vim.o.columns

  damnit.options = vim.tbl_deep_extend("force", options, {
    views = opts.views or { today = "due:today | overdue" },
    sidebar = {
      side = opts.side or "left",
      width = opts.width or WIDTH,
      view = opts.view or "today",
    },
  })

  local fake = fake_dam.install({
    fixtures = TESTS_DIR .. "/fixtures/full",
    sleep = opts.answer == false and "5" or nil,
  })
  queue.reset()
  list.forget_folds()
  views.reset()

  local notifications = {}
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  vim.o.columns = 160
  vim.cmd("tabnew")
  local tab = vim.api.nvim_get_current_tabpage()

  local ok, result = pcall(body, fake)

  vim.cmd("tabclose")
  if vim.api.nvim_tabpage_is_valid(tab) then
    vim.api.nvim_set_current_tabpage(tab)
    vim.cmd("tabclose")
  end

  vim.o.columns = columns
  vim.notify = real_notify
  vim.cmd("silent! %bwipeout!")

  -- The slow-fetch case leaves a call in flight, and cancelling one that is
  -- not there says so out loud in the middle of the run.
  if queue.running() then
    queue.cancel()
  end
  queue.reset()
  views.reset()
  fake_dam.remove(fake)
  damnit.options = options

  assert(ok, result)

  return result, notifications
end

--- Wait for the view in the sidebar to have been drawn from dam's answer.
---@param win integer
local function drawn(win)
  fake_dam.settle(function()
    return vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win)) > 3
  end)
end

---@return integer count windows in this tabpage
local function windows()
  return #vim.api.nvim_tabpage_list_wins(0)
end

--- Put the cursor on the line of `win`'s buffer holding `needle`.
---@param win integer
---@param needle string
local function cursor_to(win, needle)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)) do
    if line:find(needle, 1, true) then
      vim.api.nvim_win_set_cursor(win, { index, 0 })

      return
    end
  end

  error("no line holds " .. needle)
end

return {
  ["toggle opens a fixed-width split and a second call closes it"] = function()
    in_tab({}, function()
      local before = windows()

      local win = sidebar.toggle()
      assert(win, "toggle opened nothing")
      assert(windows() == before + 1, "windows: " .. windows())
      assert(vim.api.nvim_win_get_width(win) == WIDTH, vim.api.nvim_win_get_width(win))
      drawn(win)

      sidebar.toggle()
      assert(windows() == before, "windows after the second toggle: " .. windows())
      assert(not sidebar.window(), "a sidebar window is still marked")
    end)
  end,

  ["the width survives another window opening and an equalizing command"] = function()
    in_tab({}, function()
      local win = sidebar.toggle()
      drawn(win)

      vim.cmd("vsplit")
      assert(vim.api.nvim_win_get_width(win) == WIDTH, "after vsplit: " .. vim.api.nvim_win_get_width(win))

      vim.cmd("split")
      assert(vim.api.nvim_win_get_width(win) == WIDTH, "after split: " .. vim.api.nvim_win_get_width(win))

      vim.cmd("wincmd =")
      assert(vim.api.nvim_win_get_width(win) == WIDTH, "after wincmd =: " .. vim.api.nvim_win_get_width(win))

      vim.cmd("wincmd p")
      vim.cmd("close")
      assert(vim.api.nvim_win_get_width(win) == WIDTH, "after a close: " .. vim.api.nvim_win_get_width(win))
    end)
  end,

  ["the width comes back once the only window in the tabpage has company"] = function()
    in_tab({}, function()
      local win = sidebar.toggle()
      drawn(win)

      vim.api.nvim_set_current_win(win)
      vim.cmd("only")
      vim.cmd("vsplit")

      assert(vim.api.nvim_win_get_width(win) == WIDTH, "after standing alone: " .. vim.api.nvim_win_get_width(win))
    end)
  end,

  ["the side comes from config"] = function()
    in_tab({ side = "left" }, function()
      local win = sidebar.toggle()
      drawn(win)
      assert(vim.api.nvim_win_get_position(win)[2] == 0, "a left sidebar is not at column 0")
    end)

    in_tab({ side = "right" }, function()
      local win = sidebar.toggle()
      drawn(win)
      local column = vim.api.nvim_win_get_position(win)[2]
      assert(column + vim.api.nvim_win_get_width(win) >= vim.o.columns - 1, "a right sidebar is not at the far edge")
    end)
  end,

  ["a side it cannot read leaves the layout alone"] = function()
    local _, notifications = in_tab({ side = "up" }, function()
      local before = windows()
      sidebar.toggle()
      assert(windows() == before, "the layout changed")
    end)

    assert(#notifications == 1, vim.inspect(notifications))
    assert(notifications[1]:find("sidebar.side", 1, true), notifications[1])
  end,

  ["a width that is not a count of columns leaves the layout alone"] = function()
    local _, notifications = in_tab({ width = 0 }, function()
      local before = windows()
      sidebar.toggle()
      assert(windows() == before, "the layout changed")
    end)

    assert(#notifications == 1, vim.inspect(notifications))
    assert(notifications[1]:find("sidebar.width", 1, true), notifications[1])
  end,

  ["a view dam has already refused leaves the layout alone"] = function()
    local _, notifications = in_tab({ view = "tomorrow" }, function()
      -- What the list records when dam answers `parse` on a bare name: the name
      -- is a view in neither source, so the second attempt costs no call.
      views.forget_filter("tomorrow")

      local before = windows()
      sidebar.toggle()
      assert(windows() == before, "the layout changed")
    end)

    assert(#notifications == 1, vim.inspect(notifications))
    assert(notifications[1]:find('no view named "tomorrow"', 1, true), notifications[1])
  end,

  ["a sidebar closed with :q leaves no idea of an open one behind"] = function()
    in_tab({}, function()
      local win = sidebar.toggle()
      drawn(win)

      vim.api.nvim_set_current_win(win)
      vim.cmd("quit")

      assert(not sidebar.window(), "the closed window is still the sidebar")

      local reopened = sidebar.toggle()
      assert(reopened and reopened ~= win, "toggle did not open a new sidebar")
      assert(vim.api.nvim_win_get_width(reopened) == WIDTH, vim.api.nvim_win_get_width(reopened))
    end)
  end,

  ["it says it is loading while the first fetch is out"] = function()
    in_tab({ answer = false }, function()
      local win = sidebar.toggle()
      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)

      assert(lines[1]:find("today", 1, true), vim.inspect(lines))
      assert(vim.tbl_contains(lines, "Loading..."), vim.inspect(lines))
    end)
  end,

  ["another buffer cannot be opened into the sidebar"] = function()
    in_tab({}, function()
      local win = sidebar.toggle()
      drawn(win)
      local held = vim.api.nvim_win_get_buf(win)

      local ok = pcall(vim.api.nvim_win_set_buf, win, vim.api.nvim_create_buf(false, true))

      assert(not ok, "a foreign buffer was accepted")
      assert(vim.api.nvim_win_get_buf(win) == held, "the sidebar lost its list")
    end)
  end,

  ["opening an object from the sidebar lands beside it, not inside it"] = function()
    in_tab({}, function()
      local win = sidebar.toggle()
      drawn(win)
      local held = vim.api.nvim_win_get_buf(win)

      cursor_to(win, "buy oat milk")
      vim.api.nvim_set_current_win(win)
      list.open_under_cursor()

      assert(vim.api.nvim_get_current_win() ~= win, "the object opened into the sidebar")
      assert(sidebar.window() == win, "the sidebar window is gone")
      assert(vim.api.nvim_win_get_buf(win) == held, "the sidebar lost its list")
    end)
  end,

  ["opening an object with the sidebar alone in the tabpage splits rather than erroring"] = function()
    in_tab({}, function()
      local win = sidebar.toggle()
      drawn(win)

      cursor_to(win, "buy oat milk")
      vim.api.nvim_set_current_win(win)
      vim.cmd("only")

      local before = windows()
      local ok, err = pcall(list.open_under_cursor)

      assert(ok, "opening an object with the sidebar alone raised: " .. tostring(err))
      assert(windows() == before + 1, "no split was made for the object: " .. windows())
      assert(sidebar.window() == win, "the sidebar window is gone")
    end)
  end,

  ["gd from the sidebar opens the file beside it"] = function()
    in_tab({}, function()
      local root = vim.fs.normalize(vim.fn.tempname())
      vim.fn.mkdir(root .. "/lua", "p")
      local handle = assert(io.open(root .. "/lua/list.lua", "w"))
      handle:write("one\ntwo\nthree\n")
      handle:close()

      local win = sidebar.toggle()
      drawn(win)
      local held = vim.api.nvim_win_get_buf(win)

      cursor_to(win, "hold the sidebar width")
      vim.api.nvim_set_current_win(win)
      vim.cmd.tcd(vim.fn.fnameescape(root))

      -- The fixture's body points into `damnit.nvim`, and the tabpage is in a
      -- directory of its own, so the location is rewritten to this one's name.
      local jumped = location_edit.jump({ path = "lua/list.lua", line = 2 })

      assert(jumped, "the jump was refused")
      assert(vim.api.nvim_get_current_win() ~= win, "the file opened into the sidebar")
      assert(vim.api.nvim_win_get_buf(win) == held, "the sidebar lost its list")
      assert(vim.endswith(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), "/lua/list.lua"), "the wrong file opened")
    end)
  end,

  ["toggle in another tabpage opens one there rather than closing the first"] = function()
    in_tab({}, function()
      local first = sidebar.toggle()
      drawn(first)

      vim.cmd("tabnew")
      local second = sidebar.toggle()

      assert(second and second ~= first, "the second tabpage got no sidebar of its own")
      assert(vim.api.nvim_win_is_valid(first), "the first tabpage's sidebar was closed")
    end)
  end,
}
