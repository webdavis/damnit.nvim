-- What <CR> opens, and what it leaves alone.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local status_window = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/status_window.lua")

---@return string[]
local function open_buffer_names()
  local names = {}

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    names[#names + 1] = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
  end

  return names
end

return {
  ["opens a conflict as ours and theirs, side by side and unmodifiable"] = function()
    status_window.with(function()
      vim.api.nvim_feedkeys("gc", "x", false)
      vim.api.nvim_feedkeys("\r", "x", false)

      local names = open_buffer_names()
      local ours, theirs = false, false

      for _, name in ipairs(names) do
        ours = ours or name:find("ours", 1, true) ~= nil
        theirs = theirs or name:find("theirs", 1, true) ~= nil
      end

      assert(ours and theirs, vim.inspect(names))

      local sides = 0
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)

        if vim.api.nvim_buf_get_name(buf):find("damnit://conflict", 1, true) then
          sides = sides + 1
          assert(vim.bo[buf].modifiable == false, "a conflict side is read only")

          local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
          assert(body:find("shared shopping list", 1, true), body)
        end
      end

      assert(sides == 2, ("%d conflict sides are open"):format(sides))
    end)
  end,

  ["opens a remote's unpushed commits, newest first"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gp", "x", false)
      local status_buf = vim.api.nvim_get_current_buf()
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("\r", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(fake_dam.argv_log(fake)[before + 1] == "log --json", vim.inspect(fake_dam.argv_log(fake)))

      fake_dam.settle(function()
        return vim.api.nvim_buf_get_name(0):find("damnit://unpushed/fake", 1, true) ~= nil
      end)

      local buf = vim.api.nvim_get_current_buf()
      local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")

      assert(vim.bo[buf].modifiable == false, "the commit listing is read only")
      assert(body:find("7257572", 1, true), body)
      assert(body:find("stage the shopping list", 1, true), body)
      assert(body:find("buy oat milk", 1, true), body)

      -- fake is one commit behind, so the older one is not drawn.
      assert(not body:find("renew the passport", 1, true), body)

      -- dam skips past a commit whose objects failed and marks later ones
      -- pushed, so the newest are not necessarily the unpushed ones.
      assert(body:find("the newest 1 commit", 1, true), body)
      assert(body:find("1 unpushed", 1, true), body)
      assert(body:find("dam does not name which commits are unpushed", 1, true), body)

      -- The listing splits, the way a conflict does, so the status stays open.
      local shown = false
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        shown = shown or vim.api.nvim_win_get_buf(win) == status_buf
      end
      assert(shown, "the status window survives the listing")
    end)
  end,

  ["refuses a remote with nothing unpushed rather than reading the log"] = function()
    status_window.with(function(fake, notifications)
      local before = #fake_dam.argv_log(fake)

      require("damnit.open").unpushed({ kind = "remote", remote = "flaky", commits = 0 })

      assert(#fake_dam.argv_log(fake) == before, "nothing was sent")
      assert(
        notifications[#notifications] == "damnit.nvim: this remote has no commit on this line",
        notifications[#notifications]
      )
    end)
  end,

  ["does nothing on a heading or a notice"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gn", "x", false)
      local before = #fake_dam.argv_log(fake)
      local windows = #vim.api.nvim_list_wins()
      vim.api.nvim_feedkeys("\r", "x", false)

      assert(#fake_dam.argv_log(fake) == before, "nothing was sent")
      assert(#vim.api.nvim_list_wins() == windows, "nothing was opened")
    end)
  end,
}
