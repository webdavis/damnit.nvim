-- The status window: one per store, re-read rather than patched, and the keys
-- that move around it.

dofile(((arg[0]:match("(.*)/") or ".") .. "/../plugin/damnit.lua"))

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local queue = require("damnit.queue")
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
