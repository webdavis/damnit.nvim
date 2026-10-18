local TESTS_DIR = arg[0]:match("(.*)/") or "."

local fake_process = dofile(TESTS_DIR .. "/helpers/fake_process.lua")
local list_buffer = dofile(TESTS_DIR .. "/helpers/list_buffer.lua")
local function queue()
  return require("damnit").app().queue
end

local EIGHT_OBJECTS = TESTS_DIR .. "/fixtures/long"

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
    list_buffer.with(function(buf, fake)
      vim.api.nvim_win_set_cursor(0, { 8, 0 })
      local before = #fake_process.argv_log(fake)

      vim.api.nvim_feedkeys("p", "x", false)
      fake_process.settle(function()
        return #fake_process.argv_log(fake) >= before + 2 and queue().running() == nil
      end)

      local line = vim.api.nvim_win_get_cursor(0)[1]
      assert(line == 8, ("the cursor moved to line %d"):format(line))
      assert(
        vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] == "- write the quarterly report",
        vim.inspect(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      )
    end, { fixtures = EIGHT_OBJECTS })
  end,

  ["R leaves the drawn list on screen until dam's answer replaces it"] = function()
    list_buffer.with(function(buf, fake)
      local seen = every_redraw_of(buf)
      local before = #fake_process.argv_log(fake)

      vim.api.nvim_feedkeys("R", "x", false)
      fake_process.settle(function()
        return #fake_process.argv_log(fake) > before and queue().running() == nil
      end)

      assert(#seen >= 1, "dam's answer never redrew the list")
      for _, lines in ipairs(seen) do
        assert(not vim.tbl_contains(lines, "Loading..."), vim.inspect(lines))
      end
    end)
  end,
}
