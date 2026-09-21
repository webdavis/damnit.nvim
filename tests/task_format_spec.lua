-- The task buffer's text: that it round-trips, what it refuses, and what a
-- write sends. Pure functions over tables and lines, so no buffer and no
-- request appear here.

local format = require("damnit.task_format")

--- One task as the API describes it.
---@param overrides table?
---@return table
local function task(overrides)
  return vim.tbl_extend("force", {
    id = "6XGgmFVcrG5RRjVr",
    content = "Buy oat milk",
    description = "The kind in the grey carton.\n\n- [ ] check the date",
    due = { string = "tomorrow 9am", date = "2026-09-18" },
    priority = 3,
    labels = { "errands", "home" },
    project_id = "2203306141",
    section_id = "7025",
  }, overrides or {})
end

---@param overrides table?
---@return table header
---@return string description
local function read_back(overrides)
  local header, description, err = format.parse(format.render(task(overrides)))
  assert(not err, err)

  return header, description
end

return {
  ["renders the header as markdown frontmatter and the description below it"] = function()
    local lines = format.render(task())

    assert(lines[1] == "---", lines[1])
    assert(lines[2] == "content: Buy oat milk", lines[2])
    assert(lines[3] == "due: tomorrow 9am", lines[3])
    assert(lines[4] == "priority: 3", lines[4])
    assert(lines[5] == "labels: errands, home", lines[5])
    assert(lines[6] == "project: 2203306141", lines[6])
    assert(lines[7] == "section: 7025", lines[7])
    assert(lines[8] == "---", lines[8])
    assert(lines[9] == "The kind in the grey carton.", lines[9])
    assert(lines[10] == "", lines[10])
    assert(lines[11] == "- [ ] check the date", lines[11])
  end,

  ["round-trips a task through the text and back with nothing to send"] = function()
    local original = task()
    local header, description = read_back()

    assert(header.content == original.content, header.content)
    assert(description == original.description, vim.inspect(description))

    local fields, err = format.changes(original, header, description)
    assert(not err, err)
    assert(vim.tbl_isempty(fields), vim.inspect(fields))
  end,

  ["round-trips a task with no due date, no labels and no section"] = function()
    local bare = { id = "1", content = "Think", description = "", priority = 1, labels = {}, project_id = "2" }

    local header, description, unreadable = format.parse(format.render(bare))
    assert(not unreadable, unreadable)

    assert(header.due == "", vim.inspect(header))
    assert(header.section == "", vim.inspect(header))
    assert(description == "", vim.inspect(description))

    local fields, err = format.changes(bare, header, description)
    assert(not err, err)
    assert(vim.tbl_isempty(fields), vim.inspect(fields))
  end,

  ["sends only the fields that changed"] = function()
    local header, description = read_back()
    header.content = "Buy oat milk and bread"
    header.priority = "4"
    header.labels = "home,  errands "

    local fields, err = format.changes(task(), header, description .. "\n- [ ] and the lid")
    assert(not err, err)

    assert(fields.content == "Buy oat milk and bread", vim.inspect(fields))
    assert(fields.priority == 4, vim.inspect(fields))
    assert(fields.description:find("and the lid", 1, true), vim.inspect(fields))
    assert(fields.due_string == nil, "an unchanged due string was sent, which would reparse it")
    assert(vim.deep_equal(fields.labels, { "home", "errands" }), vim.inspect(fields.labels))
  end,

  ["sends a due string only when it changed"] = function()
    local header, description = read_back()
    header.due = "every monday"

    local fields = format.changes(task(), header, description)
    assert(fields.due_string == "every monday", vim.inspect(fields))
  end,

  ["refuses a buffer with no opening fence"] = function()
    local _, _, err = format.parse({ "content: Buy milk", "---" })
    assert(err and err:find("first line"), vim.inspect(err))
  end,

  ["refuses a buffer with no closing fence"] = function()
    local _, _, err = format.parse({ "---", "content: Buy milk" })
    assert(err and err:find("closing"), vim.inspect(err))
  end,

  ["refuses a header line that is not a key and a value"] = function()
    local _, _, err = format.parse({ "---", "content: Buy milk", "tomorrow 9am", "---" })
    assert(err and err:find("line 3"), vim.inspect(err))
  end,

  ["refuses an unknown header field rather than dropping it"] = function()
    local _, _, err = format.parse({ "---", "priorty: 2", "---" })
    assert(err and err:find("priorty"), vim.inspect(err))
  end,

  ["refuses a repeated header field"] = function()
    local _, _, err = format.parse({ "---", "due: today", "due: tomorrow", "---" })
    assert(err and err:find("repeats"), vim.inspect(err))
  end,

  ["refuses a header missing a field"] = function()
    local _, _, err = format.parse({ "---", "content: Buy milk", "---" })
    assert(err and err:find("missing"), vim.inspect(err))
    assert(err:find("priority"), vim.inspect(err))
  end,

  ["refuses an empty content"] = function()
    local header, description = read_back()
    header.content = ""

    local fields, err = format.changes(task(), header, description)
    assert(not fields, vim.inspect(fields))
    assert(err:find("content"), err)
  end,

  ["refuses a priority the API has no room for"] = function()
    local header, description = read_back()

    for _, bad in ipairs({ "0", "5", "high", "2.5", "" }) do
      header.priority = bad
      local fields, err = format.changes(task(), header, description)
      assert(not fields, bad .. " was accepted")
      assert(err:find("priority"), err)
    end
  end,

  ["refuses a move dressed up as an edit"] = function()
    local header, description = read_back()
    header.project = "9999"

    local fields, err = format.changes(task(), header, description)
    assert(not fields, vim.inspect(fields))
    assert(err:find("moving a task"), err)
  end,
}
