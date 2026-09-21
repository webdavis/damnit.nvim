-- The completed history: one query, drawn flat, newest completion first.

local TESTS_DIR = arg[0]:match("(.*)/") or "."

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local list_buffer = dofile(TESTS_DIR .. "/helpers/list_buffer.lua")
local damnit = require("damnit")

local REPORT = "37b186f6e73ed2c4d25a4854023c694e6bec8715"

--- Open the history against the `done` fixtures and hand it to `run`.
---@param run fun(buf: integer, fake: damnit.FakeDam, notifications: string[])
local function history(run)
  list_buffer.with(run, {
    fixtures = TESTS_DIR .. "/fixtures/done",
    open = function()
      return damnit.completed()
    end,
  })
end

return {
  ["asks dam for the done objects in one call"] = function()
    history(function(_, fake)
      local reads = 0
      for _, line in ipairs(fake_dam.argv_log(fake)) do
        if vim.startswith(line, "ls ") then
          reads = reads + 1
        end
      end

      assert(vim.tbl_contains(fake_dam.argv_log(fake), "ls done --json"), vim.inspect(fake_dam.argv_log(fake)))
      assert(reads == 1, "the whole history is one query, so there is nothing to page")
    end)
  end,

  ["draws it flat, newest completion first"] = function()
    history(function(buf)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

      -- dam answers a query in path order, so the document's own order is
      -- bins, rent, report while the completions ran rent, bins, report.
      local subjects = {}
      for index = 3, #lines do
        local subject = lines[index]:match("^%-%s(.-)%s%s")
        if subject then
          subjects[#subjects + 1] = subject
        end
      end

      assert(vim.deep_equal(subjects, { "filed the report", "took out the bins", "paid the rent" }), vim.inspect(lines))

      for index = 3, #lines do
        if lines[index] ~= "" then
          assert(not lines[index]:match("^%s"), "no line is indented: " .. lines[index])
        end
      end
    end)
  end,

  ["u reopens the object the cursor is on"] = function()
    history(function(buf, fake)
      list_buffer.cursor_to(buf, "filed the report")
      local before = #fake_dam.argv_log(fake)

      vim.api.nvim_feedkeys("u", "x", false)
      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(
        fake_dam.argv_log(fake)[before + 1] == ("edit %s --undone --json"):format(REPORT),
        vim.inspect(fake_dam.argv_log(fake))
      )
    end)
  end,
}
