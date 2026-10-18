local with_dam = require("helpers.harness").with_dam
local harness = require("helpers.harness")
local fake_process = require("helpers.fake_process")
local status_window = require("helpers.status_window")
local said = require("helpers.said")

local CONFLICT = "f3784324d2d2793b7daa6c532887b034bd365ddf"

return {
  ["P pushes every remote, re-reads the remote list a push moves, and reports dam's own counts"] = function()
    with_dam(status_window.opts(), function(dam)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("P", "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before + 2
      end)

      local log = fake_process.argv_log(dam.fake)
      assert(log[before + 1] == "push --json", vim.inspect(log))
      assert(log[before + 2] == "remote list --json", "a push moves what each remote last had: " .. vim.inspect(log))
      assert(log[before + 3] == "status --json", vim.inspect(log))

      assert(#dam.said == 1, vim.inspect(dam.said))
      assert(
        said.whole(
          dam.said[1],
          "damnit.nvim: fake: 3 sent, 3 ok, 0 failed, 0 skipped; flaky: 7 sent, 6 ok, 1 failed, 0 skipped"
        ),
        vim.inspect(dam.said)
      )
    end)
  end,

  ["P on a remote's line pushes only that remote"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.api.nvim_feedkeys("gp", "x", false)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("P", "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before
      end)

      assert(
        fake_process.argv_log(dam.fake)[before + 1] == "push fake --json",
        vim.inspect(fake_process.argv_log(dam.fake))
      )
    end)
  end,

  ["p pulls and reports what arrived"] = function()
    with_dam(status_window.opts(), function(dam)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("p", "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before
      end)

      assert(fake_process.argv_log(dam.fake)[before + 1] == "pull --json", vim.inspect(fake_process.argv_log(dam.fake)))

      fake_process.settle(function()
        return table.concat(dam.said, "\n"):find("fake: 2 new, 1 updated, 0 conflicts", 1, true) ~= nil
      end)
    end)
  end,

  ["a credential failure says where to fix it, beside dam's own line"] = function()
    with_dam(status_window.opts(), function(dam)
      local before = #fake_process.argv_log(dam.fake)

      dam.fake.stderr =
        '{"error":{"kind":"credential","rule":null,"message":"no credential for remote \\"fake\\"","oids":[]}}'
      dam.fake.exit = 1

      vim.api.nvim_feedkeys("p", "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before
      end)

      dam.fake.stderr, dam.fake.exit = nil, nil

      fake_process.settle(function()
        return #dam.said >= 1
      end)

      assert(#dam.said == 1, vim.inspect(dam.said))
      assert(
        said.whole(
          dam.said[1],
          'damnit.nvim: no credential for remote "fake"; if its source is a command that prompts, '
            .. "run dam pull in a terminal, and otherwise fix the source in dam's config"
        ),
        vim.inspect(dam.said)
      )
    end)
  end,

  ["co and ct resolve the conflict under the cursor"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.api.nvim_feedkeys("gc", "x", false)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("co", "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before
      end)

      assert(
        fake_process.argv_log(dam.fake)[before + 1] == ("resolve %s --ours --json"):format(CONFLICT),
        vim.inspect(fake_process.argv_log(dam.fake))
      )
    end)
  end,

  ["ct anywhere else sends nothing"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.api.nvim_feedkeys("gu", "x", false)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("ct", "x", false)

      assert(#fake_process.argv_log(dam.fake) == before)
      assert(dam.said[#dam.said] == "damnit.nvim: no conflict on this line", dam.said[#dam.said])
    end)
  end,

  ["says there is nothing to push, as plain information, when no remote is behind"] = function()
    with_dam(status_window.opts({ fixtures = harness.fixtures("default") }), function(dam)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("P", "x", false)

      assert(#fake_process.argv_log(dam.fake) == before)
      assert(dam.said[#dam.said] == "damnit.nvim: nothing to push", dam.said[#dam.said])
      assert(dam.fake.levels[#dam.said] == vim.log.levels.INFO, tostring(dam.fake.levels[#dam.said]))
    end)
  end,

  ["says there is nothing to pull when dam has no remote"] = function()
    with_dam(status_window.opts({ fixtures = harness.fixtures("default") }), function(dam)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("p", "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before and #dam.said > 0
      end)

      assert(vim.deep_equal(dam.said, { "damnit.nvim: nothing to pull" }), vim.inspect(dam.said))
    end)
  end,
}
