local with_dam = require("helpers.harness").with_dam
local harness = require("helpers.harness")
local fake_process = require("helpers.fake_process")
local status_window = require("helpers.status_window")

local WORKING_UPDATE = "badb4903b653809e591c31118004e07de7c8183c"
local WORKING_DELETE = "e648ce077ff286a30e5d984a2d93a24739e090ad"
local STAGED_CREATE = "5cf398f699045d551091eccc347f6b70f41f9bcf"

return {
  ["- stages the change under the cursor"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.api.nvim_feedkeys("gu", "x", false)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("-", "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before + 1
      end)

      local log = fake_process.argv_log(dam.fake)
      assert(log[before + 1] == ("add %s --json"):format(WORKING_UPDATE), vim.inspect(log))
      assert(log[before + 2] == "status --json", "the window re-reads rather than patching itself")
    end)
  end,

  ["- on a staged change sends reset instead"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.api.nvim_feedkeys("gs", "x", false)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("-", "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before
      end)

      assert(
        fake_process.argv_log(dam.fake)[before + 1] == ("reset %s --json"):format(STAGED_CREATE),
        vim.inspect(fake_process.argv_log(dam.fake))
      )
    end)
  end,

  ["a heading stages every change in its section in one call"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.api.nvim_feedkeys("gu", "x", false)
      vim.api.nvim_feedkeys("k", "x", false)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("s", "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before
      end)

      local sent = fake_process.argv_log(dam.fake)[before + 1]
      assert(sent:find("^add "), sent)
      assert(sent:find(WORKING_UPDATE, 1, true), sent)
      assert(sent:find(WORKING_DELETE, 1, true), sent)
    end)
  end,

  ["a visual range stages what it covers and no heading"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.api.nvim_feedkeys("gu", "x", false)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("Vj", "x", false)
      vim.api.nvim_feedkeys("s", "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before
      end)

      local sent = fake_process.argv_log(dam.fake)[before + 1]
      assert(sent == ("add %s %s --json"):format(WORKING_UPDATE, WORKING_DELETE), sent)
    end)
  end,

  ["s on something already staged sends nothing and says so"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.api.nvim_feedkeys("gs", "x", false)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("s", "x", false)

      assert(#fake_process.argv_log(dam.fake) == before, "nothing was sent")
      assert(dam.said[#dam.said] == "damnit.nvim: already staged", dam.said[#dam.said])
    end)
  end,

  ["staging keys do nothing on a notice or a conflict line"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.api.nvim_feedkeys("gc", "x", false)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("-", "x", false)

      assert(#fake_process.argv_log(dam.fake) == before)
      assert(dam.said[#dam.said] == "damnit.nvim: nothing to stage on this line", dam.said[#dam.said])
    end)
  end,

  ["U unstages everything"] = function()
    with_dam(status_window.opts(), function(dam)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("U", "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before
      end)

      assert(
        fake_process.argv_log(dam.fake)[before + 1] == "reset --json",
        vim.inspect(fake_process.argv_log(dam.fake))
      )
    end)
  end,

  ["U says nothing is staged when nothing is"] = function()
    with_dam(status_window.opts({ fixtures = harness.fixtures("default") }), function(dam)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("U", "x", false)

      assert(#fake_process.argv_log(dam.fake) == before, "nothing was sent")
      assert(dam.said[#dam.said] == "damnit.nvim: nothing is staged", dam.said[#dam.said])
    end)
  end,
}
