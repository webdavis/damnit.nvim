-- The rendering of a list, as pure functions over tables.

local format = require("todoist.list_format")
local location = require("todoist.location")

--- The sidebar's default width, which is the narrowest a list is drawn at.
local SIDEBAR_WIDTH = 40

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

  ["draws a task whose labels came back null"] = function()
    assert(format.task_line({ content = "Tidy up", labels = vim.NIL }, "") == "  - Tidy up")
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

  ["a task captured from code carries the location icon, and one without carries none"] = function()
    local captured = { id = "a", content = "Hold the width", description = "todoist.nvim lua/todoist/list.lua:42" }
    local plain = { id = "b", content = "Buy milk", description = "at the shop on the corner" }

    assert(vim.endswith(format.task_line(captured, "", location.parse(captured.description)), location.ICON))
    assert(not format.task_line(plain, "", location.parse(plain.description)):find(location.ICON, 1, true))
  end,

  ["render hands back the location each line holds, for the jump that follows"] = function()
    local captured = { id = "a", content = "Hold the width", project_id = "1", description = "repo lua/list.lua:42" }
    local plain = { id = "b", content = "Buy milk", project_id = "1" }

    local lines, _, locations = format.render({ title = "t" }, { captured, plain }, PROJECTS, SECTIONS)

    local where = locations[line_of(lines, "Hold the width")]
    assert(where and where.path == "lua/list.lua" and where.line == 42, vim.inspect(locations))
    assert(locations[line_of(lines, "Buy milk")] == nil, vim.inspect(locations))
  end,

  ["the icon goes last, so it cannot push content out of a 40-column sidebar"] = function()
    local task = {
      id = "a",
      content = "Hold the sidebar at the width it was configured with",
      description = "todoist.nvim lua/todoist/sidebar.lua:42",
    }

    local with_icon = format.task_line(task, "", location.parse(task.description))
    local without = format.task_line(task, "", nil)

    assert(with_icon:sub(1, SIDEBAR_WIDTH) == without:sub(1, SIDEBAR_WIDTH), with_icon)
    assert(#without > SIDEBAR_WIDTH, "the case needs a line longer than the sidebar to prove anything")
  end,

  ["renders a flat list of top-level tasks exactly as it did before subtasks"] = function()
    local nulled = {}
    for index, task in ipairs(TASKS) do
      nulled[index] = vim.tbl_extend("force", task, { parent_id = vim.NIL })
    end

    local plain = joined(format.render({ title = "all open tasks" }, TASKS, PROJECTS, SECTIONS))
    local with_nulls = joined(format.render({ title = "all open tasks" }, nulled, PROJECTS, SECTIONS))

    assert(plain == with_nulls, with_nulls)
    assert(plain:find("Errands\n  - Buy milk", 1, true), plain)
  end,

  ["draws a parent's children under it, one level further in"] = function()
    local lines, ids = format.render({ title = "t" }, {
      { id = "p", content = "Ship the release", project_id = "1", parent_id = vim.NIL },
      { id = "c1", content = "Tag it", project_id = "1", parent_id = "p" },
      { id = "c2", content = "Write the notes", project_id = "1", parent_id = "p" },
    }, PROJECTS, SECTIONS)

    assert(joined(lines):find("  - Ship the release\n    - Tag it\n    - Write the notes", 1, true), joined(lines))
    assert(ids[line_of(lines, "Tag it")] == "c1", vim.inspect(ids))
    assert(ids[line_of(lines, "Write the notes")] == "c2", vim.inspect(ids))
  end,

  ["draws three levels, each one indent further in than the last"] = function()
    local lines = format.render({ title = "t" }, {
      { id = "p", content = "Ship the release", project_id = "2", section_id = "9", parent_id = vim.NIL },
      { id = "c", content = "Tag it", project_id = "2", section_id = "9", parent_id = "p" },
      { id = "g", content = "Sign the tag", project_id = "2", section_id = "9", parent_id = "c" },
    }, PROJECTS, SECTIONS)

    assert(joined(lines):find("    - Ship the release\n      - Tag it\n        - Sign the tag", 1, true), joined(lines))
  end,

  ["a subtask whose parent this view does not hold is drawn at the top level"] = function()
    local lines, ids = format.render({ title = "today", filter = "today" }, {
      { id = "c", content = "Tag it", project_id = "1", parent_id = "p" },
    }, PROJECTS, SECTIONS)

    assert(joined(lines):find("Errands\n  - Tag it", 1, true), joined(lines))
    assert(ids[line_of(lines, "Tag it")] == "c", vim.inspect(ids))
    assert(not joined(lines):find("No tasks.", 1, true), joined(lines))
  end,

  ["a collapsed task is drawn without its subtasks, and says how many went"] = function()
    local tasks = {
      { id = "p", content = "Ship the release", project_id = "1", parent_id = vim.NIL },
      { id = "c", content = "Tag it", project_id = "1", parent_id = "p" },
      { id = "g", content = "Sign the tag", project_id = "1", parent_id = "c" },
    }

    local lines, ids = format.render({ title = "t" }, tasks, PROJECTS, SECTIONS, { p = true })

    assert(joined(lines):find("  - Ship the release  (+2)", 1, true), joined(lines))
    assert(not joined(lines):find("Tag it", 1, true), joined(lines))
    assert(not joined(lines):find("Sign the tag", 1, true), joined(lines))

    local mapped = 0
    for _ in pairs(ids) do
      mapped = mapped + 1
    end
    assert(mapped == 1, vim.inspect(ids))
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
