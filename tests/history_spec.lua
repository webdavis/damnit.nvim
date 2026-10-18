local with_dam = require("helpers.harness").with_dam
local harness = require("helpers.harness")

local fake_process = require("helpers.fake_process")
local list_buffer = require("helpers.list_buffer")
local damnit = require("damnit")

local REPORT = "37b186f6e73ed2c4d25a4854023c694e6bec8715"

local function history_over_the_done_fixtures(run)
  with_dam(
    list_buffer.opts({
      fixtures = harness.fixtures("done"),
      open = function()
        return damnit.completed()
      end,
    }),
    run
  )
end

return {
  ["asks dam for the done objects in one call"] = function()
    history_over_the_done_fixtures(function(dam)
      local reads = 0
      for _, line in ipairs(fake_process.argv_log(dam.fake)) do
        if vim.startswith(line, "ls ") then
          reads = reads + 1
        end
      end

      assert(
        vim.tbl_contains(fake_process.argv_log(dam.fake), "ls done --json"),
        vim.inspect(fake_process.argv_log(dam.fake))
      )
      assert(reads == 1, "the whole history is one query, so there is nothing to page")
    end)
  end,

  ["draws it flat, newest completion first"] = function()
    history_over_the_done_fixtures(function(dam)
      local lines = vim.api.nvim_buf_get_lines(dam.buf, 0, -1, false)

      local subjects = {}
      for index = 3, #lines do
        local subject = lines[index]:match("^%-%s(.-)%s%s")
        if subject then
          subjects[#subjects + 1] = subject
        end
      end

      local newest_completion_first = { "filed the report", "took out the bins", "paid the rent" }
      local dams_path_order = { "took out the bins", "paid the rent", "filed the report" }
      assert(not vim.deep_equal(newest_completion_first, dams_path_order))
      assert(vim.deep_equal(subjects, newest_completion_first), vim.inspect(lines))

      for index = 3, #lines do
        if lines[index] ~= "" then
          assert(not lines[index]:match("^%s"), "no line is indented: " .. lines[index])
        end
      end
    end)
  end,

  ["u reopens the object the cursor is on"] = function()
    history_over_the_done_fixtures(function(dam)
      list_buffer.cursor_to(dam.buf, "filed the report")
      local before = #fake_process.argv_log(dam.fake)

      vim.api.nvim_feedkeys("u", "x", false)
      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before
      end)

      assert(
        fake_process.argv_log(dam.fake)[before + 1] == ("edit %s --undone --json"):format(REPORT),
        vim.inspect(fake_process.argv_log(dam.fake))
      )
    end)
  end,
}
