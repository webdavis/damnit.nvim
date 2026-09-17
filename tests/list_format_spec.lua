-- The rendering of a list, as pure functions over tables.

local format = require("todoist.list_format")

local PROJECTS = {
  { id = "1", name = "Errands" },
  { id = "2", name = "Work" },
}

local SECTIONS = {
  { id = "9", project_id = "2", name = "Sprint" },
}

local TASKS = {
  { id = "a", content = "Buy milk", project_id = "1", priority = 1 },
  { id = "b", content = "Review the branch", project_id = "2", section_id = "9", priority = 4 },
  { id = "c", content = "File the receipt", project_id = "2", priority = 1 },
}

--- The number of the one line holding `needle`, so an assertion names a task
--- rather than counting the headings above it.
---@param lines string[]
---@param needle string
---@return integer
local function line_of(lines, needle)
  local found = nil

  for number, line in ipairs(lines) do
    if line:find(needle, 1, true) then
      assert(found == nil, needle .. " is on more than one line")
      found = number
    end
  end

  assert(found, needle .. " is on no line: " .. table.concat(lines, "\n"))

  return found
end

---@param lines string[]
---@return string
local function joined(lines)
  return table.concat(lines, "\n")
end

return {
  ["names the view, and the filter when there is one"] = function()
    assert(format.title({ title = "all open tasks" }) == "Todoist: all open tasks")
    assert(format.title({ title = "today", filter = "today | overdue" }) == "Todoist: today  (today | overdue)")
  end,

  ["puts a task's due date, priority and labels on its line"] = function()
    local line = format.task_line({
      content = "Pay rent",
      priority = 3,
      labels = { "home", "money" },
      due = { date = "2026-10-01", string = "1 oct" },
    }, "")

    assert(line == "  - Pay rent  (2026-10-01)  p3  @home  @money", line)
  end,

  ["falls back to the due string when the API recorded no date"] = function()
    local line = format.task_line({ content = "Call back", due = { string = "every monday" } }, "")

    assert(line == "  - Call back  (every monday)", line)
  end,

  ["leaves priority off a task that has none"] = function()
    assert(format.task_line({ content = "Tidy up", priority = 1 }, "") == "  - Tidy up")
  end,

  ["groups tasks by project and then by section, in the API's order"] = function()
    local lines = format.render({ title = "all open tasks" }, TASKS, PROJECTS, SECTIONS)

    assert(
      joined(lines):find(
        table.concat({
          "Errands",
          "  - Buy milk",
          "",
          "Work",
          "  - File the receipt",
          "  Sprint",
          "    - Review the branch",
        }, "\n"),
        1,
        true
      ),
      joined(lines)
    )
  end,

  ["maps every task line back to its id and leaves headings unmapped"] = function()
    local lines, ids = format.render({ title = "all open tasks" }, TASKS, PROJECTS, SECTIONS)

    assert(ids[line_of(lines, "Buy milk")] == "a", vim.inspect(ids))
    assert(ids[line_of(lines, "Review the branch")] == "b", vim.inspect(ids))
    assert(ids[line_of(lines, "File the receipt")] == "c", vim.inspect(ids))
    assert(ids[line_of(lines, "Errands")] == nil, "a project heading held a task id")
    assert(ids[line_of(lines, "Sprint")] == nil, "a section heading held a task id")

    local mapped = 0
    for _ in pairs(ids) do
      mapped = mapped + 1
    end
    assert(mapped == 3, vim.inspect(ids))
  end,

  ["heads a group the API did not name with the id, rather than dropping it"] = function()
    local lines, ids = format.render({ title = "all open tasks" }, {
      { id = "z", content = "Stray", project_id = "404", section_id = "505" },
    }, PROJECTS, SECTIONS)

    assert(joined(lines):find("404\n  505\n    - Stray", 1, true), joined(lines))
    assert(vim.tbl_contains(vim.tbl_values(ids), "z"), vim.inspect(ids))
  end,

  ["heads a task with no project_id at all with a literal, not a blank line"] = function()
    local lines, ids = format.render({ title = "t" }, {
      { id = "z", content = "Orphan" },
    }, {}, {})

    assert(joined(lines):find("(no project)\n  - Orphan", 1, true), joined(lines))
    assert(ids[line_of(lines, "Orphan")] == "z", vim.inspect(ids))
  end,

  ["says a view matched nothing rather than rendering nothing"] = function()
    local lines, ids = format.render({ title = "today", filter = "today" }, {}, PROJECTS, SECTIONS)

    assert(lines[#lines] == "No tasks.", joined(lines))
    assert(next(ids) == nil, vim.inspect(ids))
  end,

  ["reports a refusal in the API's own wording"] = function()
    local lines = format.refusal(
      { title = "broken", filter = "due befor: tomorrow" },
      { kind = "http", status = 400, message = "Invalid query: unexpected token" }
    )

    assert(joined(lines):find("The API refused this view:", 1, true), joined(lines))
    assert(joined(lines):find("Invalid query: unexpected token", 1, true), joined(lines))
    assert(not joined(lines):find("No tasks.", 1, true), joined(lines))
  end,
}
