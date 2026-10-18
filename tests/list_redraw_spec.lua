local with_dam = require("helpers.harness").with_dam
local harness = require("helpers.harness")

local fake_process = require("helpers.fake_process")
local list_buffer = require("helpers.list_buffer")
local function queue()
  return require("damnit").app().queue
end

local EIGHT_OBJECTS = harness.fixtures("long")

local function every_redraw_of(buf)
  local seen = {}

  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      table.insert(seen, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end,
  })

  return seen
end

return {
  ["p keeps the cursor on the object it was on"] = function()
    with_dam(list_buffer.opts({ fixtures = EIGHT_OBJECTS }), function(dam)
      vim.api.nvim_win_set_cursor(0, { 8, 0 })
      local before = #fake_process.argv_log(dam.fake)

      vim.api.nvim_feedkeys("p", "x", false)
      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) >= before + 2 and queue().running() == nil
      end)

      local line = vim.api.nvim_win_get_cursor(0)[1]
      assert(line == 8, ("the cursor moved to line %d"):format(line))
      assert(
        vim.api.nvim_buf_get_lines(dam.buf, line - 1, line, false)[1] == "- write the quarterly report",
        vim.inspect(vim.api.nvim_buf_get_lines(dam.buf, 0, -1, false))
      )
    end)
  end,

  ["R leaves the drawn list on screen until dam's answer replaces it"] = function()
    with_dam(list_buffer.opts(), function(dam)
      local seen = every_redraw_of(dam.buf)
      local before = #fake_process.argv_log(dam.fake)

      vim.api.nvim_feedkeys("R", "x", false)
      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before and queue().running() == nil
      end)

      assert(#seen >= 1, "dam's answer never redrew the list")
      for _, lines in ipairs(seen) do
        assert(not vim.tbl_contains(lines, "Loading..."), vim.inspect(lines))
      end
    end)
  end,
}
