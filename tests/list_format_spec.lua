-- The rendering of a list, as pure functions over dam's own objects.

local format = require("damnit.list_format")
local location = require("damnit.location")

--- The sidebar's default width, which is the narrowest a list is drawn at.
local SIDEBAR_WIDTH = 40

---@param fields table
---@return table
local function object(fields)
  return vim.tbl_extend("force", {
    oid = ("%040x"):format(#tostring(fields.subject or "")),
    kind = "task",
    subject = "an object",
    body = "",
    path = "",
    labels = {},
    depends = {},
    reminders = {},
    task = { done = false, priority = 4 },
  }, fields)
end

local PARENT = object({ subject = "Ship the release", path = "work/release/" })
local CHILD = object({ subject = "Tag it", path = "work/release/tag/" })
local GRANDCHILD = object({ subject = "Sign the tag", path = "work/release/tag/sign/" })

--- The number of the one line holding `needle`.
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
  ["names the view, and the query when there is one"] = function()
    assert(format.title({ title = "all open tasks" }) == "dam: all open tasks")
    assert(format.title({ title = "today", query = "due:today | overdue" }) == "dam: today  (due:today | overdue)")
  end,

  ["puts an object's due date, priority and labels on its line"] = function()
    local line = format.object_line(
      object({
        subject = "Pay rent",
        labels = { "home", "money" },
        task = { done = false, priority = 2, due = "2026-10-01" },
      }),
      ""
    )

    assert(line == "- Pay rent  (2026-10-01)  p2  @home  @money", line)
  end,

  ["leaves the priority off an object at dam's least urgent"] = function()
    assert(format.object_line(object({ subject = "Tidy up" }), "") == "- Tidy up")
  end,

  ["draws an object whose labels came back null"] = function()
    assert(format.object_line(object({ subject = "Tidy up", labels = vim.NIL }), "") == "- Tidy up")
  end,

  ["puts the path last, and nothing at all for an object at the root"] = function()
    local placed = format.object_line(object({ subject = "Buy milk", path = "errands/milk/" }), "")

    assert(placed == "- Buy milk  errands/milk/", placed)
    assert(format.object_line(object({ subject = "Buy milk" }), "") == "- Buy milk")
  end,

  ["maps every line back to its object and leaves the title unmapped"] = function()
    local lines, entries = format.render({ title = "all open tasks" }, { PARENT, CHILD })

    assert(entries[line_of(lines, "Ship the release")].object == PARENT, vim.inspect(entries))
    assert(entries[line_of(lines, "Tag it")].object == CHILD, vim.inspect(entries))
    assert(entries[1] == nil, "the title line held an object")

    local mapped = 0
    for _ in pairs(entries) do
      mapped = mapped + 1
    end
    assert(mapped == 2, vim.inspect(entries))
  end,

  ["says a view matched nothing rather than rendering nothing"] = function()
    local lines, entries = format.render({ title = "today", query = "due:today" }, {})

    assert(lines[#lines] == "No objects.", joined(lines))
    assert(next(entries) == nil, vim.inspect(entries))
  end,

  ["an object captured from code carries the location icon, and one without carries none"] = function()
    local captured = object({ subject = "Hold the width", body = "damnit.nvim lua/damnit/list.lua:42" })
    local plain = object({ subject = "Buy milk", body = "at the shop on the corner" })

    assert(vim.endswith(format.object_line(captured, ""), location.ICON), format.object_line(captured, ""))
    assert(not format.object_line(plain, ""):find(location.ICON, 1, true))
  end,

  ["render hands back the location each line holds, for the jump that follows"] = function()
    local captured = object({ subject = "Hold the width", body = "repo lua/list.lua:42" })
    local plain = object({ subject = "Buy milk" })

    local lines, entries = format.render({ title = "t" }, { captured, plain })

    local where = entries[line_of(lines, "Hold the width")].location
    assert(where and where.path == "lua/list.lua" and where.line == 42, vim.inspect(entries))
    assert(entries[line_of(lines, "Buy milk")].location == nil, vim.inspect(entries))
  end,

  ["the icon goes after the subject, so it cannot push it out of a 40-column sidebar"] = function()
    local subject = "Hold the sidebar at the width it was configured with"
    local with_icon = format.object_line(object({ subject = subject, body = "damnit.nvim lua/x.lua:42" }), "")
    local without = format.object_line(object({ subject = subject }), "")

    assert(with_icon:sub(1, SIDEBAR_WIDTH) == without:sub(1, SIDEBAR_WIDTH), with_icon)
    assert(#without > SIDEBAR_WIDTH, "the case needs a line longer than the sidebar to prove anything")
  end,

  ["draws a parent's children under it, one level further in"] = function()
    local second = object({ subject = "Write the notes", path = "work/release/notes/" })
    local lines = format.render({ title = "t" }, { PARENT, CHILD, second })

    assert(joined(lines):find("- Ship the release", 1, true), joined(lines))
    assert(joined(lines):find("\n  - Tag it", 1, true), joined(lines))
    assert(joined(lines):find("\n  - Write the notes", 1, true), joined(lines))
  end,

  ["draws three levels, each one indent further in than the last"] = function()
    local lines = format.render({ title = "t" }, { PARENT, CHILD, GRANDCHILD })

    assert(
      joined(lines):find("- Ship the release  work/release/\n  - Tag it", 1, true)
        and joined(lines):find("\n    - Sign the tag", 1, true),
      joined(lines)
    )
  end,

  ["a child whose parent this view does not hold is drawn at the top level"] = function()
    local lines, entries = format.render({ title = "today", query = "due:today" }, { CHILD })

    assert(lines[3] == "- Tag it  work/release/tag/", joined(lines))
    assert(entries[3].object == CHILD, vim.inspect(entries))
    assert(not joined(lines):find("No objects.", 1, true), joined(lines))
  end,

  ["a collapsed object is drawn without its subtasks, and says how many went"] = function()
    local lines, entries = format.render({ title = "t" }, { PARENT, CHILD, GRANDCHILD }, { ["work/release/"] = true })

    assert(joined(lines):find("- Ship the release  work/release/  (+2)", 1, true), joined(lines))
    assert(not joined(lines):find("Tag it", 1, true), joined(lines))

    local mapped = 0
    for _ in pairs(entries) do
      mapped = mapped + 1
    end
    assert(mapped == 1, vim.inspect(entries))
  end,

  ["reports a refusal in dam's own wording"] = function()
    local lines = format.refusal(
      { title = "broken", query = "due befor: tomorrow" },
      { kind = "parse", code = 1, message = "unexpected befor in query" }
    )

    assert(joined(lines):find("dam refused this view:", 1, true), joined(lines))
    assert(joined(lines):find("unexpected befor in query", 1, true), joined(lines))
    assert(not joined(lines):find("No objects.", 1, true), joined(lines))
  end,
}
