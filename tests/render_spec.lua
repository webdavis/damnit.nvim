local status_fixture = require("helpers.status_fixture")

local TESTS_DIR = require("helpers.paths").TESTS

local fixture = status_fixture.read
local full_status_with_only_the_sections = status_fixture.with_only_the_sections
local lines_of = status_fixture.lines_of
local STATE = status_fixture.STATE

local function golden(name, lines)
  local path = ("%s/golden/%s.txt"):format(TESTS_DIR, name)
  local text = table.concat(
    vim.tbl_map(function(line)
      return line.text
    end, lines),
    "\n"
  ) .. "\n"

  if vim.env.DAMNIT_GOLDEN_UPDATE == "1" then
    vim.fn.mkdir(("%s/golden"):format(TESTS_DIR), "p")
    local out = assert(io.open(path, "w"))
    out:write(text)
    out:close()

    return
  end

  local file = assert(io.open(path, "r"), "no golden at " .. path .. "; regenerate with DAMNIT_GOLDEN_UPDATE=1")
  local want = file:read("*a")
  file:close()

  assert(
    text == want,
    ("golden %s differs; regenerate with DAMNIT_GOLDEN_UPDATE=1 and read the diff before committing it\n"):format(name)
      .. ("--- got ---\n%s--- want ---\n%s"):format(text, want)
  )
end

return {
  ["draws an empty store as dam's own sentence"] = function()
    local lines = lines_of(fixture("default/status.json"))
    golden("empty", lines)

    assert(lines[#lines].text == "nothing staged, nothing changed", lines[#lines].text)
  end,

  ["draws each section on its own"] = function()
    golden("working", lines_of(full_status_with_only_the_sections("unstaged")))
    golden("staged", lines_of(full_status_with_only_the_sections("staged")))
    golden("unpushed", lines_of(full_status_with_only_the_sections("unpushed")))
    golden("notices", lines_of(full_status_with_only_the_sections("notices")))
    golden("conflicts", lines_of(full_status_with_only_the_sections("conflicts")))
  end,

  ["draws every section at once, conflicts first"] = function()
    golden("full", lines_of(fixture("full/status.json")))
  end,

  ["puts the running operation and its elapsed time in the header"] = function()
    local state = {
      store = STATE.store,
      now = STATE.now,
      running = { label = "push todoist", elapsed = 12.34, pending = 2 },
    }
    local lines = lines_of(fixture("full/status.json"), state)
    golden("running", lines)

    assert(lines[3].text:find("push todoist", 1, true), lines[3].text)
    assert(lines[3].text:find("12.3s", 1, true), lines[3].text)
    assert(lines[3].text:find("(2 queued)", 1, true), lines[3].text)
  end,

  ["puts a space after a segment too wide for its column"] = function()
    local wide = {
      unstaged = {
        {
          oid = "badb4903b653809e591c31118004e07de7c8183c",
          op = "update",
          fields = { "subject" },
          kind = "task",
          subject = ("s"):rep(60),
          path = "inbox/",
          labels = {},
        },
      },
    }

    local line = nil
    for _, each in ipairs(lines_of(wide)) do
      if each.kind == "change" then
        line = each
        break
      end
    end

    assert(line.text:find("s %(subject%)"), line.text)
    assert(line.text:find("%(subject%) inbox/"), line.text)
  end,
}
