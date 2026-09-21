-- The commit message buffer: what it carries, what :w sends, and what it
-- refuses to send.

local commit_buffer = require("damnit.commit_buffer")
local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local status_window = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/status_window.lua")

---@param notifications string[]
---@param text string
---@return boolean
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
    status_window.with(function()
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
    status_window.with(function(fake, notifications)
      vim.api.nvim_feedkeys("cc", "x", false)
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "buy the milk" })

      local before = #fake_dam.argv_log(fake)
      vim.cmd("write")

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(
        fake_dam.argv_log(fake)[before + 1] == "commit -m buy the milk --json",
        vim.inspect(fake_dam.argv_log(fake))
      )

      fake_dam.settle(function()
        return said(notifications, "damnit.nvim: 7257572 committed, 2 changes")
      end)

      assert(not vim.api.nvim_buf_is_valid(buf), "the message buffer is gone once the commit is made")
    end)
  end,

  ["refuses to commit an empty message and keeps the buffer open"] = function()
    status_window.with(function(fake, notifications)
      vim.api.nvim_feedkeys("cc", "x", false)
      local buf = vim.api.nvim_get_current_buf()
      local before = #fake_dam.argv_log(fake)

      vim.cmd("write")

      assert(#fake_dam.argv_log(fake) == before, "nothing was sent")
      assert(vim.api.nvim_buf_is_valid(buf), "the buffer stays open to be fixed")
      assert(
        notifications[#notifications] == "damnit.nvim: no commit message; the commit was not made",
        notifications[#notifications]
      )
    end)
  end,

  ["says nothing is staged when nothing is"] = function()
    status_window.with(function(fake, notifications)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("cc", "x", false)

      assert(#fake_dam.argv_log(fake) == before, "nothing was sent")
      assert(vim.bo.filetype == "damstatus", "no message buffer opened")
      assert(notifications[#notifications] == "damnit.nvim: nothing is staged to commit", notifications[#notifications])
    end, (arg[0]:match("(.*)/") or ".") .. "/fixtures/default")
  end,
}
