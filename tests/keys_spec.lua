-- Every staging key in the status window, asserted by the argv the fake dam
-- recorded.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local status_window = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/status_window.lua")

local WORKING_UPDATE = "badb4903b653809e591c31118004e07de7c8183c"
local WORKING_DELETE = "e648ce077ff286a30e5d984a2d93a24739e090ad"
local STAGED_CREATE = "5cf398f699045d551091eccc347f6b70f41f9bcf"

return {
  ["- stages the change under the cursor"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gu", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("-", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before + 1
      end)

      local log = fake_dam.argv_log(fake)
      assert(log[before + 1] == ("add %s --json"):format(WORKING_UPDATE), vim.inspect(log))
      assert(log[before + 2] == "status --json", "the window re-reads rather than patching itself")
    end)
  end,

  ["- on a staged change sends reset instead"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gs", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("-", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(
        fake_dam.argv_log(fake)[before + 1] == ("reset %s --json"):format(STAGED_CREATE),
        vim.inspect(fake_dam.argv_log(fake))
      )
    end)
  end,

  ["a heading stages every change in its section in one call"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gu", "x", false)
      vim.api.nvim_feedkeys("k", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("s", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      local sent = fake_dam.argv_log(fake)[before + 1]
      assert(sent:find("^add "), sent)
      assert(sent:find(WORKING_UPDATE, 1, true), sent)
      assert(sent:find(WORKING_DELETE, 1, true), sent)
    end)
  end,

  ["a visual range stages what it covers and no heading"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gu", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("Vj", "x", false)
      vim.api.nvim_feedkeys("s", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      local sent = fake_dam.argv_log(fake)[before + 1]
      assert(sent == ("add %s %s --json"):format(WORKING_UPDATE, WORKING_DELETE), sent)
    end)
  end,

  ["s on something already staged sends nothing and says so"] = function()
    status_window.with(function(fake, notifications)
      vim.api.nvim_feedkeys("gs", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("s", "x", false)

      assert(#fake_dam.argv_log(fake) == before, "nothing was sent")
      assert(notifications[#notifications] == "damnit.nvim: already staged", notifications[#notifications])
    end)
  end,

  ["staging keys do nothing on a notice or a conflict line"] = function()
    status_window.with(function(fake, notifications)
      vim.api.nvim_feedkeys("gc", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("-", "x", false)

      assert(#fake_dam.argv_log(fake) == before)
      assert(
        notifications[#notifications] == "damnit.nvim: nothing to stage on this line",
        notifications[#notifications]
      )
    end)
  end,

  ["U unstages everything"] = function()
    status_window.with(function(fake)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("U", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(fake_dam.argv_log(fake)[before + 1] == "reset --json", vim.inspect(fake_dam.argv_log(fake)))
    end)
  end,

  ["U says nothing is staged when nothing is"] = function()
    status_window.with(function(fake, notifications)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("U", "x", false)

      assert(#fake_dam.argv_log(fake) == before, "nothing was sent")
      assert(notifications[#notifications] == "damnit.nvim: nothing is staged", notifications[#notifications])
    end, (arg[0]:match("(.*)/") or ".") .. "/fixtures/default")
  end,
}
