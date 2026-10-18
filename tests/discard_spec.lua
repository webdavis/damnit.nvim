local with_dam = require("helpers.harness").with_dam
local fake_process = require("helpers.fake_process")
local status_window = require("helpers.status_window")

local STAGED_CREATE = "5cf398f699045d551091eccc347f6b70f41f9bcf"
local UNSTAGED_UPDATE = "badb4903b653809e591c31118004e07de7c8183c"
local UNSTAGED_DELETE = "e648ce077ff286a30e5d984a2d93a24739e090ad"

return {
  ["X removes an uncommitted create after a confirm"] = function()
    with_dam(status_window.opts({ input = status_window.answering("y") }), function(dam)
      vim.api.nvim_feedkeys("gs", "x", false)
      local before = #fake_process.argv_log(dam.fake)

      vim.api.nvim_feedkeys("X", "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before
      end)

      assert(
        fake_process.argv_log(dam.fake)[before + 1] == ("rm %s --json"):format(STAGED_CREATE),
        vim.inspect(fake_process.argv_log(dam.fake))
      )
    end)
  end,

  ["X sends nothing when the confirm is answered no"] = function()
    with_dam(status_window.opts({ input = status_window.answering(nil) }), function(dam)
      vim.api.nvim_feedkeys("gs", "x", false)
      local before = #fake_process.argv_log(dam.fake)

      vim.api.nvim_feedkeys("X", "x", false)

      assert(#fake_process.argv_log(dam.fake) == before, vim.inspect(fake_process.argv_log(dam.fake)))
    end)
  end,

  ["X restores an update to its committed state after a confirm"] = function()
    local asked
    local function remember(prompt)
      asked = prompt
    end

    with_dam(status_window.opts({ input = status_window.answering("y", remember) }), function(dam)
      vim.api.nvim_feedkeys("gu", "x", false)
      local before = #fake_process.argv_log(dam.fake)

      vim.api.nvim_feedkeys("X", "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before
      end)

      assert(
        fake_process.argv_log(dam.fake)[before + 1] == ("restore %s --json"):format(UNSTAGED_UPDATE),
        vim.inspect(fake_process.argv_log(dam.fake))
      )
      assert(asked:find("back to its last commit", 1, true), asked)
    end)
  end,

  ["X restores a delete, bringing the object back"] = function()
    with_dam(status_window.opts({ input = status_window.answering("y") }), function(dam)
      vim.api.nvim_feedkeys("gu", "x", false)
      vim.api.nvim_feedkeys("j", "x", false)
      local before = #fake_process.argv_log(dam.fake)

      vim.api.nvim_feedkeys("X", "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before
      end)

      assert(
        fake_process.argv_log(dam.fake)[before + 1] == ("restore %s --json"):format(UNSTAGED_DELETE),
        vim.inspect(fake_process.argv_log(dam.fake))
      )
    end)
  end,
}
