local with_dam = require("helpers.harness").with_dam
local app = require("damnit").app()
local fake_process = require("helpers.fake_process")
local status_window = require("helpers.status_window")
local window = require("damnit.window")

return {
  ["opens one buffer per store and focuses it rather than opening a second"] = function()
    with_dam(status_window.opts(), function()
      local first = window.buffer(app)
      vim.cmd("wincmd p")
      local second = window.open(app)

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
    with_dam(status_window.opts(), function()
      local buf = window.buffer(app)

      assert(vim.bo[buf].filetype == "damstatus", vim.bo[buf].filetype)
      assert(vim.bo[buf].buftype == "nofile", vim.bo[buf].buftype)
      assert(vim.bo[buf].bufhidden == "hide", vim.bo[buf].bufhidden)
      assert(vim.bo[buf].modifiable == false)
      assert(vim.bo[buf].buflisted == false)
      assert(vim.bo[buf].swapfile == false)
    end)
  end,

  [":Dam says its usage, prefixed, for a word it does not know"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.cmd("Dam bogus")

      local said = dam.said[#dam.said]
      local one_member_of_a_list_that_grows_with_every_subcommand = ":Dam cancel"
      assert(vim.startswith(tostring(said), "damnit.nvim: usage is :Dam, "), tostring(said))
      assert(tostring(said):find(one_member_of_a_list_that_grows_with_every_subcommand, 1, true), tostring(said))
    end)
  end,

  ["says so rather than raising E444 when the window is the only one"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.cmd("only")
      local buf = window.buffer(app)
      vim.api.nvim_feedkeys("q", "x", false)

      assert(vim.api.nvim_win_get_buf(0) == buf, "the status window is still open")
      assert(
        dam.said[#dam.said] == "damnit.nvim: the status window is the only window open",
        tostring(dam.said[#dam.said])
      )
    end)
  end,

  ["reads the status from dam rather than guessing at it"] = function()
    with_dam(status_window.opts(), function(dam)
      local log = fake_process.argv_log(dam.fake)

      assert(vim.tbl_contains(log, "status --json"), vim.inspect(log))
      assert(vim.tbl_contains(log, "remote list --json"), vim.inspect(log))
      assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:find("Store:", 1, true), "the header is drawn")
    end)
  end,

  ["q hides the window and keeps the buffer"] = function()
    with_dam(status_window.opts(), function()
      local buf = window.buffer(app)
      vim.api.nvim_feedkeys("q", "x", false)

      assert(vim.api.nvim_buf_is_valid(buf), "the buffer survives, so a re-open is instant")
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        assert(vim.api.nvim_win_get_buf(win) ~= buf, "no window still shows it")
      end
    end)
  end,

  [":Dam cancel says nothing is running when nothing is"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.cmd("Dam cancel")

      assert(dam.said[#dam.said] == "damnit.nvim: nothing is running", dam.said[#dam.said])
    end)
  end,
}
