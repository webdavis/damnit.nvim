-- The sidebar: a fixed-width split holding one view.
--
-- Nothing here reaches Todoist. The four list requests are replaced with fakes
-- on the client module, so a case controls whether an answer arrives at all,
-- which is how the in-flight state is pinned.
--
-- Each case runs in a tabpage of its own, so one case's layout is never another
-- case's starting point.

local todoist = require("damnit")
local client = require("damnit.client")
local sidebar = require("damnit.sidebar")

local WIDTH = 34

local REQUESTS = { "get_tasks", "get_tasks_matching", "get_projects", "get_sections" }

--- Run `body` in its own tabpage, with the sidebar configured and the client's
--- list requests faked. `answer` false leaves every request unanswered, which
--- is what a slow first fetch looks like.
---@param opts { side: string?, width: integer?, view: string?, views: table?, answer: boolean? }
---@param body fun(): any
---@return any result
---@return string[] notifications
local function in_tab(opts, body)
  local options = todoist.options
  local real = {}
  for _, name in ipairs(REQUESTS) do
    real[name] = client[name]
  end
  local real_notify = vim.notify
  local columns = vim.o.columns

  todoist.options = vim.tbl_deep_extend("force", options, {
    views = opts.views or { today = "today | overdue" },
    sidebar = {
      side = opts.side or "left",
      width = opts.width or WIDTH,
      view = opts.view or "today",
    },
  })

  for _, name in ipairs(REQUESTS) do
    client[name] = function(...)
      local callback = select(select("#", ...), ...)
      if opts.answer ~= false then
        callback({})
      end
    end
  end

  local notifications = {}
  vim.notify = function(message)
    table.insert(notifications, message)
  end

  vim.o.columns = 160
  vim.cmd("tabnew")
  local tab = vim.api.nvim_get_current_tabpage()

  local ok, result = pcall(body)

  vim.cmd("tabclose")
  if vim.api.nvim_tabpage_is_valid(tab) then
    vim.api.nvim_set_current_tabpage(tab)
    vim.cmd("tabclose")
  end

  vim.o.columns = columns
  vim.notify = real_notify
  for _, name in ipairs(REQUESTS) do
    client[name] = real[name]
  end
  todoist.options = options

  assert(ok, result)

  return result, notifications
end

---@return integer count windows in this tabpage
local function windows()
  return #vim.api.nvim_tabpage_list_wins(0)
end

return {
  ["toggle opens a fixed-width split and a second call closes it"] = function()
    in_tab({}, function()
      local before = windows()

      local win = sidebar.toggle()
      assert(win, "toggle opened nothing")
      assert(windows() == before + 1, "windows: " .. windows())
      assert(vim.api.nvim_win_get_width(win) == WIDTH, vim.api.nvim_win_get_width(win))

      sidebar.toggle()
      assert(windows() == before, "windows after the second toggle: " .. windows())
      assert(not sidebar.window(), "a sidebar window is still marked")
    end)
  end,

  ["the width survives another window opening and an equalizing command"] = function()
    in_tab({}, function()
      local win = sidebar.toggle()

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

      vim.api.nvim_set_current_win(win)
      vim.cmd("only")
      vim.cmd("vsplit")

      assert(vim.api.nvim_win_get_width(win) == WIDTH, "after standing alone: " .. vim.api.nvim_win_get_width(win))
    end)
  end,

  ["the side comes from config"] = function()
    in_tab({ side = "left" }, function()
      local win = sidebar.toggle()
      assert(vim.api.nvim_win_get_position(win)[2] == 0, "a left sidebar is not at column 0")
    end)

    in_tab({ side = "right" }, function()
      local win = sidebar.toggle()
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

  ["a view it was never given leaves the layout alone"] = function()
    local _, notifications = in_tab({ view = "tomorrow" }, function()
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
      local held = vim.api.nvim_win_get_buf(win)

      local ok = pcall(vim.api.nvim_win_set_buf, win, vim.api.nvim_create_buf(false, true))

      assert(not ok, "a foreign buffer was accepted")
      assert(vim.api.nvim_win_get_buf(win) == held, "the sidebar lost its list")
    end)
  end,

  ["opening a task from the sidebar lands beside it, not inside it"] = function()
    in_tab({}, function()
      client.get_tasks_matching = function(_, callback)
        callback({ { id = "T1", content = "Buy oat milk" } })
      end

      local real_get_task = client.get_task
      client.get_task = function(id, callback)
        callback({ id = id, content = "Buy oat milk" })
      end

      local sidebar_win = sidebar.toggle()
      local sidebar_buf = vim.api.nvim_win_get_buf(sidebar_win)

      local lines = vim.api.nvim_buf_get_lines(sidebar_buf, 0, -1, false)
      local task_line
      for i, line in ipairs(lines) do
        if line:find("Buy oat milk", 1, true) then
          task_line = i
        end
      end
      assert(task_line, vim.inspect(lines))
      vim.api.nvim_win_set_cursor(sidebar_win, { task_line, 0 })

      require("damnit.list").open_task_under_cursor()
      client.get_task = real_get_task

      assert(vim.api.nvim_get_current_win() ~= sidebar_win, "the task opened into the sidebar")
      assert(sidebar.window() == sidebar_win, "the sidebar window is gone")
      assert(vim.api.nvim_win_get_buf(sidebar_win) == sidebar_buf, "the sidebar lost its list")
    end)
  end,

  ["opening a task with the sidebar alone in the tabpage splits rather than erroring"] = function()
    in_tab({}, function()
      client.get_tasks_matching = function(_, callback)
        callback({ { id = "T1", content = "Buy oat milk" } })
      end

      local real_get_task = client.get_task
      client.get_task = function(id, callback)
        callback({ id = id, content = "Buy oat milk" })
      end

      local sidebar_win = sidebar.toggle()
      vim.api.nvim_set_current_win(sidebar_win)
      vim.cmd("only")

      local before = windows()
      local ok = pcall(require("damnit.task_buffer").open, "T1")
      client.get_task = real_get_task

      assert(ok, "opening a task with the sidebar alone raised an error")
      assert(windows() == before + 1, "no split was made for the task: " .. windows())
      assert(sidebar.window() == sidebar_win, "the sidebar window is gone")
    end)
  end,

  ["toggle in another tabpage opens one there rather than closing the first"] = function()
    in_tab({}, function()
      local first = sidebar.toggle()

      vim.cmd("tabnew")
      local second = sidebar.toggle()

      assert(second and second ~= first, "the second tabpage got no sidebar of its own")
      assert(vim.api.nvim_win_is_valid(first), "the first tabpage's sidebar was closed")
    end)
  end,
}
