-- The status window: one per store, re-read rather than patched, and the keys
-- that move around it.

dofile(((arg[0]:match("(.*)/") or ".") .. "/../plugin/damnit.lua"))

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local queue = require("damnit.queue")
local render = require("damnit.render")
local window = require("damnit.window")

local TESTS_DIR = arg[0]:match("(.*)/") or "."

---@param run fun(fake: damnit.FakeDam, notifications: string[])
---@param fixtures string?
local function with_window(run, fixtures)
  local fake = fake_dam.install({ fixtures = fixtures or (TESTS_DIR .. "/fixtures/full") })
  queue.reset()

  -- The remote list is read once per store and cached, so a case that asserts
  -- on it starts from a store this session has not read yet.
  window.forget_remotes()

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local buf = window.open()
  fake_dam.settle(function()
    return queue.running() == nil and vim.api.nvim_buf_line_count(buf) > 1
  end)

  local ok, err = pcall(run, fake, notifications)

  vim.notify = real
  vim.cmd("silent! %bwipeout!")
  queue.reset()
  fake_dam.remove(fake)

  assert(ok, err)
end

return {
  ["opens one buffer per store and focuses it rather than opening a second"] = function()
    with_window(function()
      local first = window.buffer()
      vim.cmd("wincmd p")
      local second = window.open()

      assert(first == second, "a second :Dam focuses the buffer the first opened")

      local shown = 0
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == first then
          shown = shown + 1
        end
      end
      assert(shown == 1, ("the buffer is in %d windows"):format(shown))
    end)
  end,

  ["writes the running operation into the header on a tick"] = function()
    with_window(function(fake)
      local buf = window.buffer()
      local before = #fake_dam.argv_log(fake)

      -- Called directly rather than through the queue's listener: window.lua
      -- registers one at load and queue.reset() drops it before this file runs.
      queue.submit({ args = { "status", "--json" }, label = "push fake" })

      -- The first tick adds a header line, so it redraws in full. The second
      -- is the one the timer repeats every 250 ms, on the header alone.
      window.tick(queue.key())
      window.tick(queue.key())

      local header = vim.api.nvim_buf_get_lines(buf, 0, 4, false)
      assert(header[3]:find("Running: push fake", 1, true), vim.inspect(header))
      assert(header[3]:find("[C-c to cancel]", 1, true), header[3])

      -- The header-only rewrite replaces the lines, which takes their extmarks
      -- with it, so every header row is re-marked rather than left unstyled.
      for lnum = 0, 3 do
        local marks = vim.api.nvim_buf_get_extmarks(buf, render.NAMESPACE, { lnum, 0 }, { lnum, -1 }, {})
        assert(#marks > 0, ("header row %d lost every mark"):format(lnum))
      end

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before and queue.running() == nil
      end)
    end)
  end,

  ["keeps a section the user folded closed across a re-read"] = function()
    with_window(function(fake)
      local buf = window.buffer()
      local heading = nil
      for index, kind in ipairs(vim.b[buf].damnit_kinds) do
        if kind == "section" then
          heading = index
          break
        end
      end

      vim.api.nvim_win_set_cursor(0, { heading, 0 })
      vim.cmd("normal! zc")
      assert(vim.fn.foldclosed(heading) == heading, ("fold at %d: %d"):format(heading, vim.fn.foldclosed(heading)))

      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("R", "x", false)
      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before and queue.running() == nil
      end)

      assert(vim.fn.foldclosed(heading) == heading, "the re-read re-opened a section the user closed")
    end)
  end,

  ["makes the buffer unmodifiable, unlisted and scratch"] = function()
    with_window(function()
      local buf = window.buffer()

      assert(vim.bo[buf].filetype == "damstatus", vim.bo[buf].filetype)
      assert(vim.bo[buf].buftype == "nofile", vim.bo[buf].buftype)
      assert(vim.bo[buf].bufhidden == "hide", vim.bo[buf].bufhidden)
      assert(vim.bo[buf].modifiable == false)
      assert(vim.bo[buf].buflisted == false)
      assert(vim.bo[buf].swapfile == false)
    end)
  end,

  [":Dam says its usage, prefixed, for a word it does not know"] = function()
    with_window(function(_, notifications)
      vim.cmd("Dam bogus")

      assert(
        notifications[#notifications] == "damnit.nvim: usage is :Dam, :Dam cancel",
        tostring(notifications[#notifications])
      )
    end)
  end,

  ["says so rather than raising E444 when the window is the only one"] = function()
    with_window(function(_, notifications)
      vim.cmd("only")
      local buf = window.buffer()
      vim.api.nvim_feedkeys("q", "x", false)

      assert(vim.api.nvim_win_get_buf(0) == buf, "the status window is still open")
      assert(
        notifications[#notifications] == "damnit.nvim: the status window is the only window open",
        tostring(notifications[#notifications])
      )
    end)
  end,

  ["reads the status from dam rather than guessing at it"] = function()
    with_window(function(fake)
      local log = fake_dam.argv_log(fake)

      assert(vim.tbl_contains(log, "status --json"), vim.inspect(log))
      assert(vim.tbl_contains(log, "remote list --json"), vim.inspect(log))
      assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:find("Store:", 1, true), "the header is drawn")
    end)
  end,

  ["R reads the status again"] = function()
    with_window(function(fake)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("R", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(fake_dam.argv_log(fake)[before + 1] == "status --json", vim.inspect(fake_dam.argv_log(fake)))
    end)
  end,

  ["gu, gs and gc jump to a section, and a count picks the entry"] = function()
    with_window(function()
      vim.api.nvim_feedkeys("gu", "x", false)
      local unstaged = vim.api.nvim_win_get_cursor(0)[1]
      assert(vim.b[0].damnit_sections[unstaged] == "working", vim.inspect(vim.b[0].damnit_sections))

      vim.api.nvim_feedkeys("2gu", "x", false)
      assert(vim.api.nvim_win_get_cursor(0)[1] == unstaged + 1, "a count picks the second entry")

      vim.api.nvim_feedkeys("gc", "x", false)
      local conflict = vim.api.nvim_win_get_cursor(0)[1]
      assert(vim.b[0].damnit_sections[conflict] == "conflicts", tostring(vim.b[0].damnit_sections[conflict]))
    end)
  end,

  ["asks for the remote list again when the first read failed"] = function()
    with_window(function(fake)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("R", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(fake_dam.argv_log(fake)[before + 1] == "remote list --json", vim.inspect(fake_dam.argv_log(fake)))
    end, TESTS_DIR .. "/fixtures/default")
  end,

  ["refuses a jump to a section this status has none of"] = function()
    with_window(function(_, notifications)
      vim.api.nvim_feedkeys("gs", "x", false)

      assert(notifications[#notifications] == "damnit.nvim: no Staged section", notifications[#notifications])
    end, TESTS_DIR .. "/fixtures/default")
  end,

  ["q hides the window and keeps the buffer"] = function()
    with_window(function()
      local buf = window.buffer()
      vim.api.nvim_feedkeys("q", "x", false)

      assert(vim.api.nvim_buf_is_valid(buf), "the buffer survives, so a re-open is instant")
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        assert(vim.api.nvim_win_get_buf(win) ~= buf, "no window still shows it")
      end
    end)
  end,

  [":Dam cancel says nothing is running when nothing is"] = function()
    with_window(function(_, notifications)
      vim.cmd("Dam cancel")

      assert(notifications[#notifications] == "damnit.nvim: nothing is running", notifications[#notifications])
    end)
  end,
}
