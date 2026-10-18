local TESTS_DIR = require("helpers.paths").TESTS

local clock = require("helpers.clock")
local format = require("damnit.list_format")
local list_buffer = require("helpers.list_buffer")
local render = require("damnit.render")

local NOON_UTC_ON_THE_FIRST_OF_OCTOBER = 1790856000

local function marks_on(buf, needle)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:find(needle, 1, true) then
      local found = {}
      for _, mark in
        ipairs(vim.api.nvim_buf_get_extmarks(buf, render.NAMESPACE, { index - 1, 0 }, { index - 1, -1 }, {
          details = true,
        }))
      do
        found[#found + 1] = { mark[3], mark[4].end_col, mark[4].hl_group }
      end

      return found
    end
  end

  error(needle .. " is on no line")
end

local function object(task)
  return { subject = "pay rent", path = "", labels = {}, task = task }
end

return {
  ["a list colours an overdue due date, a future one, the priority and each label over their columns"] = function()
    clock.at(NOON_UTC_ON_THE_FIRST_OF_OCTOBER, function()
      list_buffer.with(function(buf)
        local overdue = marks_on(buf, "- buy oat milk  (2026-09-25)  p1  @errand  inbox/")
        assert(
          vim.deep_equal(overdue, { { 16, 28, "DamOverdue" }, { 30, 32, "DamPriority1" }, { 34, 41, "DamLabel" } }),
          vim.inspect(overdue)
        )

        local future = marks_on(buf, "- renew the passport  (2026-10-20)")
        assert(vim.deep_equal(future, { { 22, 34, "DamDue" } }), vim.inspect(future))
      end, { fixtures = TESTS_DIR .. "/fixtures/badges" })
    end)
  end,

  ["a due date of today is due, not overdue"] = function()
    local _, marks = format.object_line(object({ due = "2026-10-01" }), "", 0, "2026-10-01")
    assert(vim.deep_equal(marks, { { col = 12, length = 12, group = "DamDue" } }), vim.inspect(marks))
  end,

  ["each drawn priority takes its own group"] = function()
    for priority = 1, 3 do
      local _, marks = format.object_line(object({ priority = priority }), "", 0, "2026-10-01")
      assert(marks[1].group == "DamPriority" .. priority, vim.inspect(marks))
    end
  end,

  ["dam's least urgent priority draws no badge and no colour"] = function()
    local line, marks = format.object_line(object({ priority = 4 }), "", 0, "2026-10-01")
    assert(line == "- pay rent" and #marks == 0, line .. vim.inspect(marks))
  end,
}
