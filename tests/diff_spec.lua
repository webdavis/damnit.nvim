-- The inline field diff, and what X will and will not throw away.

local diff = require("damnit.render.diff")
local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local render = require("damnit.render")
local status_window = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/status_window.lua")

local BEFORE = { subject = "oat milk", labels = { "home" }, task = { priority = 1 } }
local AFTER = { subject = "buy oat milk", labels = { "errand", "home" }, task = { priority = 1, due = "2026-09-25" } }

local STAGED_CREATE = "5cf398f699045d551091eccc347f6b70f41f9bcf"

--- Every virtual line the window drew, as plain text.
---@return string[]
local function virt_lines()
  local buf = vim.api.nvim_get_current_buf()
  local drawn = {}

  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, render.NAMESPACE, 0, -1, { details = true })) do
    for _, chunks in ipairs((mark[4] or {}).virt_lines or {}) do
      local text = ""

      for _, chunk in ipairs(chunks) do
        text = text .. chunk[1]
      end

      drawn[#drawn + 1] = text
    end
  end

  return drawn
end

return {
  ["shows an update as old on the left and new on the right"] = function()
    local lines = diff.virt_lines({
      op = "update",
      fields = { "subject", "labels", "due" },
      before = BEFORE,
      after = AFTER,
    })

    assert(#lines == 3, vim.inspect(lines))

    local text = table.concat(
      vim.tbl_map(function(chunk)
        return chunk[1]
      end, lines[1]),
      ""
    )
    assert(text:find("subject", 1, true), text)
    assert(text:find("oat milk", 1, true), text)
    assert(text:find("buy oat milk", 1, true), text)
    assert(text:find("->", 1, true), text)
  end,

  ["shows a create as every set field with no old column"] = function()
    local lines = diff.virt_lines({ op = "create", fields = {}, after = AFTER })
    local groups = {}

    for _, chunks in ipairs(lines) do
      for _, chunk in ipairs(chunks) do
        groups[#groups + 1] = chunk[2]
      end
    end

    assert(vim.tbl_contains(groups, "DamDiffNew"), vim.inspect(groups))
    assert(not vim.tbl_contains(groups, "DamDiffOld"), vim.inspect(groups))
  end,

  ["shows a delete as every set field of before, with no new column"] = function()
    local lines = diff.virt_lines({ op = "delete", fields = {}, before = BEFORE })
    local groups = {}

    for _, chunks in ipairs(lines) do
      for _, chunk in ipairs(chunks) do
        groups[#groups + 1] = chunk[2]
      end
    end

    assert(vim.tbl_contains(groups, "DamDiffOld"), vim.inspect(groups))
    assert(not vim.tbl_contains(groups, "DamDiffNew"), vim.inspect(groups))
  end,

  ["writes a dash for a field that is not set"] = function()
    assert(diff.value(BEFORE, "due") == "-", diff.value(BEFORE, "due"))
    assert(diff.value(AFTER, "due") == "2026-09-25", diff.value(AFTER, "due"))
    assert(diff.value(AFTER, "labels") == "errand, home", diff.value(AFTER, "labels"))
  end,

  ["= reads the whole objects and draws the fields that moved"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gu", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("=", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before and #virt_lines() > 0
      end)

      assert(fake_dam.argv_log(fake)[before + 1] == "status --full --json", vim.inspect(fake_dam.argv_log(fake)))

      local drawn = table.concat(virt_lines(), "\n")
      assert(drawn:find("subject", 1, true), drawn)
      assert(drawn:find("buy oat milk", 1, true), drawn)
      assert(drawn:find("buy soy milk", 1, true), drawn)
    end)
  end,

  ["a second = closes the fields again"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gu", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("=", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before and #virt_lines() > 0
      end)

      vim.api.nvim_feedkeys("=", "x", false)
      assert(#virt_lines() == 0, vim.inspect(virt_lines()))
    end)
  end,

  ["keeps an open diff across a re-read"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gu", "x", false)
      local opened = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("=", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > opened and #virt_lines() > 0
      end)

      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("R", "x", false)
      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(#virt_lines() > 0, "the diff was forgotten by the re-read")
    end)
  end,

  ["X removes an uncommitted create after a confirm"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gs", "x", false)
      local before = #fake_dam.argv_log(fake)

      status_window.answer_input("y", function()
        vim.api.nvim_feedkeys("X", "x", false)
      end)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(
        fake_dam.argv_log(fake)[before + 1] == ("rm %s --json"):format(STAGED_CREATE),
        vim.inspect(fake_dam.argv_log(fake))
      )
    end)
  end,

  ["X sends nothing when the confirm is answered no"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gs", "x", false)
      local before = #fake_dam.argv_log(fake)

      status_window.answer_input(nil, function()
        vim.api.nvim_feedkeys("X", "x", false)
      end)

      assert(#fake_dam.argv_log(fake) == before, vim.inspect(fake_dam.argv_log(fake)))
    end)
  end,

  ["X refuses an update, because dam has no verb that restores one"] = function()
    status_window.with(function(fake, notifications)
      vim.api.nvim_feedkeys("gu", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("X", "x", false)

      assert(#fake_dam.argv_log(fake) == before, "nothing was sent")
      assert(
        notifications[#notifications]
          == "damnit.nvim: dam has no verb that restores a committed object; commit the change or edit it back",
        notifications[#notifications]
      )
    end)
  end,
}
