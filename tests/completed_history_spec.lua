-- The completed walk, as pure state over the pages handed to it. No buffer, no
-- request, no token: every page here is a table this spec wrote.

local history = require("damnit.completed_history")

--- 2026-09-17T12:00:00Z, so the windows below are the same every run.
local NOON = 1789646400

---@param tasks table[]
---@param next_cursor string?
---@return table
local function page(tasks, next_cursor)
  return { items = tasks, next_cursor = next_cursor }
end

---@param id string
---@param content string
---@param completed_at string?
---@return table
local function task(id, content, completed_at)
  return { id = id, content = content, completed_at = completed_at or vim.NIL }
end

---@param walk table
---@return string[] the task lines only, without the title or the footer
local function task_lines(walk)
  local lines, ids = walk:render()
  local only_tasks = {}

  for line, text in ipairs(lines) do
    if ids[line] then
      only_tasks[#only_tasks + 1] = text
    end
  end

  return only_tasks
end

---@param walk table
---@return string
local function footer(walk)
  local lines = walk:render()

  return lines[#lines]
end

return {
  ["the first window ends after today and reaches back three months"] = function()
    local request = history.new(NOON):request()

    assert(request.since == "2026-06-20T00:00:00Z", vim.inspect(request))
    assert(request.until_ == "2026-09-18T00:00:00Z", vim.inspect(request))
    assert(request.cursor == nil, vim.inspect(request))
  end,

  ["a page with a cursor asks for the same window again"] = function()
    local walk = history.new(NOON)

    walk:accept(page({}, "second-page"))

    local request = walk:request()
    assert(request.cursor == "second-page", vim.inspect(request))
    assert(request.since == "2026-06-20T00:00:00Z", vim.inspect(request))
  end,

  ["the last page of a window steps back to the window before it"] = function()
    local walk = history.new(NOON)

    walk:accept(page({}, nil))

    local request = walk:request()
    assert(request.since == "2026-03-22T00:00:00Z", vim.inspect(request))
    assert(request.until_ == "2026-06-20T00:00:00Z", vim.inspect(request))
    assert(request.cursor == nil, vim.inspect(request))
  end,

  ["a repeated cursor steps back instead of reading one window forever"] = function()
    local walk = history.new(NOON)
    walk:accept(page({}, "stuck"))

    walk:accept(page({}, "stuck"))

    assert(walk:request().until_ == "2026-06-20T00:00:00Z", vim.inspect(walk:request()))
  end,

  ["the walk stops at its floor and the footer names the day it read back to"] = function()
    local walk = history.new(NOON)

    for _ = 1, 12 do
      assert(not walk:spent(), "the walk ended before its floor")
      walk:accept(page({}, nil))
    end

    assert(walk:spent(), "the walk never reached its floor")
    assert(walk:request() == nil, vim.inspect(walk:request()))
    assert(footer(walk) == "0 completed tasks. Read back to 2023-10-04, which is as far as the API goes.", footer(walk))
  end,

  ["the footer of a walk with more to read says so instead"] = function()
    local walk = history.new(NOON)

    walk:accept(page({ task("1", "done", "2026-09-17T08:00:00Z") }, nil))

    assert(footer(walk) == "1 completed tasks. Move to the last line for more.", footer(walk))
  end,

  ["a line carries the completion date and the content"] = function()
    local walk = history.new(NOON)

    walk:accept(page({ task("1", "Buy milk", "2026-09-17T08:30:00Z") }, nil))

    assert(task_lines(walk)[1] == "2026-09-17  Buy milk", vim.inspect(task_lines(walk)))
  end,

  ["tasks are newest first across pages and within one day"] = function()
    local walk = history.new(NOON)

    walk:accept(page({
      task("1", "older", "2026-09-10T08:00:00Z"),
      task("2", "newest", "2026-09-17T21:30:00Z"),
    }, "second-page"))
    walk:accept(page({ task("3", "same day, earlier", "2026-09-17T06:05:00Z") }, nil))

    assert(
      vim.deep_equal(task_lines(walk), {
        "2026-09-17  newest",
        "2026-09-17  same day, earlier",
        "2026-09-10  older",
      }),
      vim.inspect(task_lines(walk))
    )
  end,

  ["a task with no completion date keeps the page and keeps the dates in their column"] = function()
    local walk = history.new(NOON)

    walk:accept(page({
      task("1", "dated", "2026-09-17T06:05:00Z"),
      task("2", "undated", nil),
    }, nil))

    -- Order is the ordering case's business; this one is about the page
    -- surviving and the dates keeping their column.
    local lines = task_lines(walk)
    assert(walk:len() == 2, vim.inspect(lines))
    assert(vim.tbl_contains(lines, "2026-09-17  dated"), vim.inspect(lines))
    assert(vim.tbl_contains(lines, "            undated"), vim.inspect(lines))
  end,

  ["a walk that read nothing says there are no completed tasks"] = function()
    local walk = history.new(NOON)

    walk:accept(page({}, nil))

    local lines = walk:render()
    assert(vim.tbl_contains(lines, "No completed tasks."), vim.inspect(lines))
  end,

  ["a status replaces the footer and the empty notice, so a walk in flight says so"] = function()
    local walk = history.new(NOON)

    local lines = walk:render("Reading completed tasks...")

    assert(lines[#lines] == "Reading completed tasks...", vim.inspect(lines))
    assert(not vim.tbl_contains(lines, "No completed tasks."), vim.inspect(lines))
  end,

  ["a forgotten task leaves the history at once"] = function()
    local walk = history.new(NOON)
    walk:accept(page({
      task("1", "first", "2026-09-17T06:00:00Z"),
      task("2", "second", "2026-09-16T06:00:00Z"),
    }, nil))

    walk:forget("1")

    assert(walk:len() == 1, vim.inspect(task_lines(walk)))
    assert(vim.deep_equal(task_lines(walk), { "2026-09-16  second" }), vim.inspect(task_lines(walk)))
  end,

  ["an id the endpoint repeats across pages is kept once"] = function()
    local walk = history.new(NOON)
    walk:accept(page({ task("1", "first", "2026-09-17T06:00:00Z") }, "second-page"))

    walk:accept(page({
      task("1", "first", "2026-09-17T06:00:00Z"),
      task("2", "second", "2026-09-16T06:00:00Z"),
    }, nil))

    assert(walk:len() == 2, vim.inspect(task_lines(walk)))
    assert(
      vim.deep_equal(task_lines(walk), { "2026-09-17  first", "2026-09-16  second" }),
      vim.inspect(task_lines(walk))
    )
  end,

  ["every line maps back to its own task id"] = function()
    local walk = history.new(NOON)
    walk:accept(page({
      task("aaa", "first", "2026-09-17T06:00:00Z"),
      task("bbb", "second", "2026-09-16T06:00:00Z"),
    }, nil))

    local lines, ids = walk:render()

    local found = {}
    for line, id in pairs(ids) do
      found[id] = lines[line]
    end

    assert(found["aaa"] == "2026-09-17  first", vim.inspect(found))
    assert(found["bbb"] == "2026-09-16  second", vim.inspect(found))
  end,
}
