-- What the window looks like, compared whole against a golden file.
--
-- A one-character change to a rendering is then a diff a reviewer can read.
-- Regenerate every golden with DAMNIT_GOLDEN_UPDATE=1 and read the diff before
-- committing it.

local render = require("damnit.render")
local status_model = require("damnit.status_model")

local TESTS_DIR = arg[0]:match("(.*)/") or "."

---@param name string
---@return table
local function fixture(name)
  local file = assert(io.open(("%s/fixtures/%s"):format(TESTS_DIR, name), "r"))
  local text = file:read("*a")
  file:close()

  return vim.json.decode(text, { luanil = { object = true } })
end

--- One status holding only the named sections, so nine window states come from
--- one fixture rather than from nine.
---@param ... string
---@return table
local function only(...)
  local full = fixture("full/status.json")
  local kept = { staged = {}, unstaged = {}, conflicts = {}, notices = {}, unpushed = {} }

  for _, name in ipairs({ ... }) do
    kept[name] = full[name]
  end

  return kept
end

local STATE = { store = "~/.local/share/dam/dam.db" }

---@param name string
---@param lines damnit.Line[]
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

  assert(text == want, ("golden %s differs\n--- got ---\n%s--- want ---\n%s"):format(name, text, want))
end

---@param status table
---@param state table?
---@return damnit.Line[]
local function lines_of(status, state)
  return render.lines(status_model.build(status, fixture("full/remote.json")), state or STATE)
end

return {
  ["draws an empty store as dam's own sentence"] = function()
    local lines = lines_of(fixture("default/status.json"))
    golden("empty", lines)

    assert(lines[#lines].text == "nothing staged, nothing changed", lines[#lines].text)
  end,

  ["draws each section on its own"] = function()
    golden("working", lines_of(only("unstaged")))
    golden("staged", lines_of(only("staged")))
    golden("unpushed", lines_of(only("unpushed")))
    golden("notices", lines_of(only("notices")))
    golden("conflicts", lines_of(only("conflicts")))
  end,

  ["draws every section at once, conflicts first"] = function()
    golden("full", lines_of(fixture("full/status.json")))
  end,

  ["puts the running operation and its elapsed time in the header"] = function()
    local state = {
      store = STATE.store,
      running = { label = "push todoist", elapsed = 12.34, pending = 2 },
    }
    local lines = lines_of(fixture("full/status.json"), state)
    golden("running", lines)

    assert(lines[3].text:find("push todoist", 1, true), lines[3].text)
    assert(lines[3].text:find("12.3s", 1, true), lines[3].text)
    assert(lines[3].text:find("(2 queued)", 1, true), lines[3].text)
  end,

  ["marks the verb, the oid and the path with their own groups"] = function()
    local lines = lines_of(only("unstaged"))

    local change = nil
    for _, line in ipairs(lines) do
      if line.kind == "change" then
        change = line
        break
      end
    end

    local groups = vim.tbl_map(function(mark)
      return mark.group
    end, change.marks)

    assert(vim.tbl_contains(groups, "DamOpChanged"), vim.inspect(groups))
    assert(vim.tbl_contains(groups, "DamOid"), vim.inspect(groups))
    assert(vim.tbl_contains(groups, "DamPath"), vim.inspect(groups))
    assert(change.oid == "78b8950b02735107aa608659dcf19f6f50adfeb1", tostring(change.oid))
  end,

  ["links every group to a standard one and writes no colour"] = function()
    for group, target in pairs(render.HIGHLIGHTS) do
      assert(type(target) == "string" and target ~= "", group)
    end

    render.define()

    local defined = vim.api.nvim_get_hl(0, { name = "DamOverdue", link = true })
    assert(defined.link == "ErrorMsg", vim.inspect(defined))
  end,
}
