local with_dam = require("helpers.harness").with_dam
local harness = require("helpers.harness")
local app = require("damnit").app()
local fake_process = require("helpers.fake_process")
local status_window = require("helpers.status_window")
local scratch = require("damnit.scratch")
local window = require("damnit.window")

return {
  ["- on the first of two Working entries leaves the cursor on the second"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.api.nvim_feedkeys("gu", "x", false)
      local line = vim.api.nvim_win_get_cursor(0)[1]
      dam.fake.fixtures = harness.fixtures("staged_first")
      local before = #fake_process.argv_log(dam.fake)

      vim.api.nvim_feedkeys("-", "x", false)
      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) >= before + 2 and app.queue.running() == nil
      end)

      local landed = vim.api.nvim_win_get_cursor(0)[1]
      assert(landed == line, ("the cursor left line %d for line %d"):format(line, landed))
      local found = window.entry_under_cursor(app)
      assert(found and found.section.kind == "working", vim.inspect(found and found.section.kind))
      assert(found.entry.oid:sub(1, 7) == "e648ce0", found.entry.oid)
    end)
  end,

  ["keeps a section the user folded closed when the re-read moves its heading"] = function()
    with_dam(status_window.opts(), function(dam)
      local buf = window.buffer(app)

      local function heading_of(kind)
        for index, row in ipairs(scratch.rows(buf)) do
          if row.kind == "section" and row.section == kind then
            return index
          end
        end

        error("no " .. kind .. " heading")
      end

      local heading = heading_of("staged")
      vim.api.nvim_win_set_cursor(0, { heading, 0 })
      vim.cmd("normal! zc")
      assert(vim.fn.foldclosed(heading) == heading, ("fold at %d: %d"):format(heading, vim.fn.foldclosed(heading)))

      local one_object_staged_so_the_staged_heading_slides_up = harness.fixtures("shifted")
      dam.fake.fixtures = one_object_staged_so_the_staged_heading_slides_up
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("R", "x", false)
      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before and app.queue.running() == nil
      end)

      local moved = heading_of("staged")
      assert(moved == heading - 1, ("heading %d did not move: %d"):format(heading, moved))
      assert(vim.fn.foldclosed(moved) == moved, "the re-read re-opened a section the user closed")
      assert(vim.fn.foldclosedend(moved) == moved + 2, tostring(vim.fn.foldclosedend(moved)))
    end)
  end,

  ["gu, gs and gc jump to a section, and a count picks the entry"] = function()
    with_dam(status_window.opts(), function()
      vim.api.nvim_feedkeys("gu", "x", false)
      local buf = vim.api.nvim_get_current_buf()
      local unstaged = vim.api.nvim_win_get_cursor(0)[1]
      assert(scratch.row(buf, unstaged).section == "working", "gu lands in Working")

      vim.api.nvim_feedkeys("2gu", "x", false)
      assert(vim.api.nvim_win_get_cursor(0)[1] == unstaged + 1, "a count picks the second entry")

      vim.api.nvim_feedkeys("gc", "x", false)
      local conflict = vim.api.nvim_win_get_cursor(0)[1]
      assert(scratch.row(buf, conflict).section == "conflicts", "gc lands in Conflicts")
    end)
  end,

  ["refuses a jump to a section this status has none of"] = function()
    with_dam(status_window.opts({ fixtures = harness.fixtures("default") }), function(dam)
      vim.api.nvim_feedkeys("gs", "x", false)

      assert(dam.said[#dam.said] == "damnit.nvim: no Staged section", dam.said[#dam.said])
    end)
  end,
}
