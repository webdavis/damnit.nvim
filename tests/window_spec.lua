-- The status window: one per store, re-read rather than patched, and the keys
-- that move around it.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local status_window = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/status_window.lua")
local queue = require("damnit.queue")
local render = require("damnit.render")
local window = require("damnit.window")

local TESTS_DIR = arg[0]:match("(.*)/") or "."
local with_window = status_window.with

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

  ["keeps a section the user folded closed when the re-read moves its heading"] = function()
    with_window(function(fake)
      local buf = window.buffer()

      ---@param kind string
      ---@return integer
      local function heading_of(kind)
        local sections = vim.b[buf].damnit_sections
        local kinds = vim.b[buf].damnit_kinds

        for index = 1, #kinds do
          if kinds[index] == "section" and sections[index] == kind then
            return index
          end
        end

        error("no " .. kind .. " heading: " .. vim.inspect(sections))
      end

      local heading = heading_of("staged")
      vim.api.nvim_win_set_cursor(0, { heading, 0 })
      vim.cmd("normal! zc")
      assert(vim.fn.foldclosed(heading) == heading, ("fold at %d: %d"):format(heading, vim.fn.foldclosed(heading)))

      -- One object moves from Working to Staged, which is what `s` does, so
      -- Staged gains a row and its heading slides up a line.
      vim.env.DAMNIT_TEST_FIXTURES = TESTS_DIR .. "/fixtures/shifted"
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("R", "x", false)
      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before and queue.running() == nil
      end)

      local moved = heading_of("staged")
      assert(moved == heading - 1, ("heading %d did not move: %d"):format(heading, moved))
      assert(vim.fn.foldclosed(moved) == moved, "the re-read re-opened a section the user closed")
      assert(vim.fn.foldclosedend(moved) == moved + 2, tostring(vim.fn.foldclosedend(moved)))
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
