local highlights = require("damnit.render.highlights")
local render = require("damnit.render")
local scratch = require("damnit.scratch")
local status_lines = require("damnit.render.status_lines")
local status_model = require("damnit.status_model")

local TESTS_DIR = require("helpers.paths").TESTS

local function fixture(name)
  local file = assert(io.open(("%s/fixtures/%s"):format(TESTS_DIR, name), "r"))
  local text = file:read("*a")
  file:close()

  return vim.json.decode(text, { luanil = { object = true } })
end

local function full_status_with_only_the_sections(...)
  local full = fixture("full/status.json")
  local kept = { staged = {}, unstaged = {}, conflicts = {}, notices = {}, unpushed = {} }

  for _, name in ipairs({ ... }) do
    kept[name] = full[name]
  end

  return kept
end

local TEN_AM_UTC_ON_THE_TWENTIETH = 1789898400

local STATE = { store = "~/.local/share/dam/dam.db", now = TEN_AM_UTC_ON_THE_TWENTIETH }

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

local function lines_of(status, state)
  return status_lines.lines(status_model.build(status, fixture("full/remote.json")), state or STATE)
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

  ["marks the verb, the oid and the path with their own groups"] = function()
    local lines = lines_of(full_status_with_only_the_sections("unstaged"))

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
    assert(change.oid == "badb4903b653809e591c31118004e07de7c8183c", tostring(change.oid))
  end,

  ["records every drawn row's kind, oid and section"] = function()
    local lines = lines_of(fixture("full/status.json"))
    local buf = vim.api.nvim_create_buf(false, true)
    render.draw(buf, lines)

    assert(#scratch.rows(buf) == #lines, ("%d rows for %d lines"):format(#scratch.rows(buf), #lines))

    for index, line in ipairs(lines) do
      local row = scratch.row(buf, index)
      assert(row.kind == line.kind, ("line %d kind %s"):format(index, tostring(row.kind)))
      assert(row.oid == line.oid, ("line %d oid %s"):format(index, tostring(row.oid)))
      assert(row.section == line.section, ("line %d section %s"):format(index, tostring(row.section)))
    end

    vim.api.nvim_buf_delete(buf, { force = true })
  end,

  ["names the section every entry and heading belongs to"] = function()
    local lines = lines_of(fixture("full/status.json"))
    local seen = {}

    for _, line in ipairs(lines) do
      if line.section then
        seen[line.section] = (seen[line.section] or 0) + 1
      end
    end

    local heading = 1
    local heading_plus_its_entries = {
      conflicts = heading + 1,
      working = heading + 2,
      staged = heading + 1,
      unpushed = heading + 2,
      notices = heading + 5,
    }
    assert(vim.deep_equal(seen, heading_plus_its_entries), vim.inspect(seen))
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

  ["says the remote list is unknown when it could not be read, not that there is none"] = function()
    local unread = status_model.build(fixture("default/status.json"), nil)
    local none = status_model.build(fixture("default/status.json"), { remotes = {} })

    assert(status_lines.lines(unread, STATE)[2].text == "Remotes: unknown", status_lines.lines(unread, STATE)[2].text)
    assert(
      status_lines.lines(none, STATE)[2].text == "Remotes: none configured",
      status_lines.lines(none, STATE)[2].text
    )
  end,

  ["says how long ago each remote pulled, against the clock in state"] = function()
    local lines = lines_of(fixture("full/status.json"))

    assert(
      lines[2].text == "Remotes: fake (1 unpushed, pulled 4m ago)  flaky (7 unpushed, never pulled)",
      lines[2].text
    )
  end,

  ["rounds a pull's age down to one unit and never into the future"] = function()
    local ages = {
      ["2026-09-20T09:59:30Z"] = "pulled just now",
      ["2026-09-20T10:05:00Z"] = "pulled just now",
      ["2026-09-20T07:00:00.123456Z"] = "pulled 3h ago",
      ["2026-09-18T09:00:00Z"] = "pulled 2d ago",
      ["2024-02-29T10:00:00Z"] = "pulled 934d ago",
    }

    for last_pull, expected in pairs(ages) do
      local model = status_model.build({}, { remotes = { { name = "r", last_pull = last_pull } } })
      local text = status_lines.lines(model, STATE)[2].text

      assert(text == ("Remotes: r (clean, %s)"):format(expected), last_pull .. ": " .. text)
    end
  end,

  ["links every group to a standard one and writes no colour"] = function()
    for group, target in pairs(highlights.HIGHLIGHTS) do
      assert(type(target) == "string" and target ~= "", group)
    end

    highlights.define()

    local defined = vim.api.nvim_get_hl(0, { name = "DamOverdue", link = true })
    assert(defined.link == "ErrorMsg", vim.inspect(defined))
  end,
}
