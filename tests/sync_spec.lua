-- Push, pull and resolve: the argv each sends, and the sentence each reports.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local status_window = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/status_window.lua")

local CONFLICT = "f3784324d2d2793b7daa6c532887b034bd365ddf"

return {
  ["P pushes every remote and reports dam's own counts"] = function()
    status_window.with(function(fake, notifications)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("P", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before + 2
      end)

      local log = fake_dam.argv_log(fake)
      assert(log[before + 1] == "push --json", vim.inspect(log))

      -- A push moves what each remote last had, so the window re-reads the
      -- remote list as well as the status.
      assert(log[before + 2] == "remote list --json", vim.inspect(log))
      assert(log[before + 3] == "status --json", vim.inspect(log))

      local said = table.concat(notifications, "\n")
      assert(said:find("fake: 3 sent, 3 ok, 0 failed, 0 skipped", 1, true), said)
      assert(said:find("flaky: 7 sent, 6 ok, 1 failed, 0 skipped", 1, true), said)
    end)
  end,

  ["P on a remote's line pushes only that remote"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gp", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("P", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(fake_dam.argv_log(fake)[before + 1] == "push fake --json", vim.inspect(fake_dam.argv_log(fake)))
    end)
  end,

  ["p pulls and reports what arrived"] = function()
    status_window.with(function(fake, notifications)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("p", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(fake_dam.argv_log(fake)[before + 1] == "pull --json", vim.inspect(fake_dam.argv_log(fake)))

      fake_dam.settle(function()
        return table.concat(notifications, "\n"):find("fake: 2 new, 1 updated, 0 conflicts", 1, true) ~= nil
      end)
    end)
  end,

  ["a credential failure says where to fix it, beside dam's own line"] = function()
    status_window.with(function(fake, notifications)
      local before = #fake_dam.argv_log(fake)

      vim.env.DAMNIT_TEST_STDERR =
        '{"error":{"kind":"credential","rule":null,"message":"no credential for remote \\"fake\\"","oids":[]}}'
      vim.env.DAMNIT_TEST_EXIT = "1"

      vim.api.nvim_feedkeys("p", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      vim.env.DAMNIT_TEST_STDERR = ""
      vim.env.DAMNIT_TEST_EXIT = ""

      fake_dam.settle(function()
        return table.concat(notifications, "\n"):find("fix the source in dam's config", 1, true) ~= nil
      end)

      local said = table.concat(notifications, "\n")
      assert(said:find('no credential for remote "fake"', 1, true), said)
    end)
  end,

  ["co and ct resolve the conflict under the cursor"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gc", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("co", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(
        fake_dam.argv_log(fake)[before + 1] == ("resolve %s --ours --json"):format(CONFLICT),
        vim.inspect(fake_dam.argv_log(fake))
      )
    end)
  end,

  ["ct anywhere else sends nothing"] = function()
    status_window.with(function(fake, notifications)
      vim.api.nvim_feedkeys("gu", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("ct", "x", false)

      assert(#fake_dam.argv_log(fake) == before)
      assert(notifications[#notifications] == "damnit.nvim: no conflict on this line", notifications[#notifications])
    end)
  end,

  ["says there is nothing to push when no remote is behind"] = function()
    status_window.with(function(fake, notifications)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("P", "x", false)

      assert(#fake_dam.argv_log(fake) == before)
      assert(notifications[#notifications] == "damnit.nvim: nothing to push", notifications[#notifications])
    end, (arg[0]:match("(.*)/") or ".") .. "/fixtures/default")
  end,
}
