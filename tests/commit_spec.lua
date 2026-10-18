local with_dam = require("helpers.harness").with_dam
local harness = require("helpers.harness")
local commit_buffer = require("damnit.commit_buffer")
local fake_process = require("helpers.fake_process")
local status_window = require("helpers.status_window")

local function said(notifications, text)
  return vim.tbl_contains(notifications, text)
end

return {
  ["strips the comment lines and trims the rest"] = function()
    local message = commit_buffer.message({ "", "buy the milk", "", "# Staged", "# new 660a08d" })

    assert(message == "buy the milk", vim.inspect(message))
  end,

  ["finds no message in a buffer that is all comments and blanks"] = function()
    assert(commit_buffer.message({ "", "# Staged", "" }) == "", "an all-comment buffer commits nothing")
  end,

  ["cc opens a buffer carrying the staged changes as comments"] = function()
    with_dam(status_window.opts(), function()
      vim.api.nvim_feedkeys("cc", "x", false)

      local buf = vim.api.nvim_get_current_buf()
      assert(vim.bo[buf].filetype == "damcommitmsg", vim.bo[buf].filetype)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert(lines[1] == "", "the cursor starts on an empty first line")

      local body = table.concat(lines, "\n")
      assert(body:find("# Staged", 1, true), body)
      assert(body:find("5cf398f", 1, true), body)
      assert(body:find("book dentist appointment", 1, true), body)
    end)
  end,

  [":w sends dam commit -m and reports dam's own counts"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.api.nvim_feedkeys("cc", "x", false)
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "buy the milk" })

      local before = #fake_process.argv_log(dam.fake)
      vim.cmd("write")

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before
      end)

      assert(
        fake_process.argv_log(dam.fake)[before + 1] == "commit -m buy the milk --json",
        vim.inspect(fake_process.argv_log(dam.fake))
      )

      fake_process.settle(function()
        return said(dam.said, "damnit.nvim: 7257572 committed, 2 changes")
      end)

      assert(not vim.api.nvim_buf_is_valid(buf), "the message buffer is gone once the commit is made")
    end)
  end,

  ["counts one change in the singular"] = function()
    with_dam(status_window.opts({ fixtures = harness.fixtures("one_change") }), function(dam)
      vim.api.nvim_feedkeys("cc", "x", false)
      vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), 0, 1, false, { "buy the oat milk" })

      local before = #fake_process.argv_log(dam.fake)
      vim.cmd("write")

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before and said(dam.said, "damnit.nvim: aa5fbcb committed, 1 change")
      end)
    end)
  end,

  ["refuses to commit an empty message and keeps the buffer open"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.api.nvim_feedkeys("cc", "x", false)
      local buf = vim.api.nvim_get_current_buf()
      local before = #fake_process.argv_log(dam.fake)

      vim.cmd("write")

      assert(#fake_process.argv_log(dam.fake) == before, "nothing was sent")
      assert(vim.api.nvim_buf_is_valid(buf), "the buffer stays open to be fixed")
      assert(dam.said[#dam.said] == "damnit.nvim: no commit message; the commit was not made", dam.said[#dam.said])
    end)
  end,

  ["says nothing is staged when nothing is"] = function()
    with_dam(status_window.opts({ fixtures = harness.fixtures("default") }), function(dam)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("cc", "x", false)

      assert(#fake_process.argv_log(dam.fake) == before, "nothing was sent")
      assert(vim.bo.filetype == "damstatus", "no message buffer opened")
      assert(dam.said[#dam.said] == "damnit.nvim: nothing is staged to commit", dam.said[#dam.said])
    end)
  end,

  ["cc twice keeps the one message buffer and what was typed in it"] = function()
    with_dam(status_window.opts(), function()
      vim.api.nvim_feedkeys("cc", "x", false)
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "buy the milk" })
      vim.cmd("wincmd p")
      local windows = #vim.api.nvim_list_wins()

      vim.v.errmsg = ""
      vim.api.nvim_feedkeys("cc", "x", false)

      assert(vim.v.errmsg == "", vim.v.errmsg)
      assert(vim.api.nvim_get_current_buf() == buf, "a second cc did not focus the message buffer")
      assert(#vim.api.nvim_list_wins() == windows, "a second cc opened another window")
      assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "buy the milk", "the typed message was lost")
    end)
  end,
}
