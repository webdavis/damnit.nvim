-- One status document into the window's model, and the field summary the window
-- draws in parentheses.

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

---@param model damnit.Model
---@param kind string
---@return damnit.Section?
local function section(model, kind)
  for _, candidate in ipairs(model.sections) do
    if candidate.kind == kind then
      return candidate
    end
  end

  return nil
end

return {
  ["renders nothing but a sentence for a status with nothing in it"] = function()
    local model = status_model.build(fixture("default/status.json"), nil)

    assert(model.empty == true, vim.inspect(model))
    assert(#model.sections == 0, vim.inspect(model.sections))
  end,

  ["leaves a remote with nothing unpushed out of the section"] = function()
    -- dam writes an unpushed row for every configured remote, zero commits
    -- included, and filters them out of its own human form.
    local model = status_model.build(fixture("clean/status.json"), fixture("full/remote.json"))

    assert(section(model, "unpushed") == nil, vim.inspect(model.sections))
    assert(model.empty == true, vim.inspect(model.sections))

    local want = { { remote = "fake", commits = 0 }, { remote = "flaky", commits = 0 } }
    assert(vim.deep_equal(model.remotes, want), vim.inspect(model.remotes))
  end,

  ["puts conflicts first, because they are the only section that blocks a pull"] = function()
    local model = status_model.build(fixture("full/status.json"), fixture("full/remote.json"))

    assert(model.sections[1].kind == "conflicts", model.sections[1].kind)
    assert(model.empty == false)
  end,

  ["orders the rest working, staged, unpushed, notices"] = function()
    local model = status_model.build(fixture("full/status.json"), fixture("full/remote.json"))
    local kinds = vim.tbl_map(function(each)
      return each.kind
    end, model.sections)

    assert(vim.deep_equal(kinds, { "conflicts", "working", "staged", "unpushed", "notices" }), vim.inspect(kinds))
  end,

  ["keeps a section whose predecessor in the order is empty"] = function()
    local status = vim.json.decode('{"staged":[],"unstaged":[],"conflicts":[],"unpushed":[],"notices":[]}')
    status.notices = { { kind = "push_failed", remote = "todoist" } }

    local model = status_model.build(status, nil)
    local kinds = vim.tbl_map(function(each)
      return each.kind
    end, model.sections)

    assert(vim.deep_equal(kinds, { "notices" }), vim.inspect(kinds))
  end,

  ["names an update's changed fields, as dam itself named them"] = function()
    local model = status_model.build(fixture("full/status.json"), nil)
    local change = section(model, "working").entries[1]

    assert(change.verb == "changed", change.verb)
    assert(change.oid == "badb4903b653809e591c31118004e07de7c8183c", change.oid)
    assert(vim.deep_equal(change.fields, { "subject", "priority" }), vim.inspect(change.fields))
  end,

  ["reads the flat change row dam writes when --full is not passed"] = function()
    local model = status_model.build(fixture("full/status.json"), nil)
    local change = section(model, "working").entries[1]

    assert(change.subject == "buy soy milk", change.subject)
    assert(change.path == "inbox/", change.path)
    assert(change.object_kind == "task", tostring(change.object_kind))
    assert(change.after == nil, "dam embeds no object without --full")
  end,

  ["falls back to the embedded objects when dam wrote no flat row"] = function()
    local nested = {
      unstaged = {
        {
          oid = "78b8950b02735107aa608659dcf19f6f50adfeb1",
          op = "update",
          before = { kind = "task", subject = "oat milk", path = "inbox/", task = { priority = 1 } },
          after = { kind = "task", subject = "buy oat milk", path = "inbox/", task = { priority = 2 } },
        },
      },
    }

    local change = section(status_model.build(nested, nil), "working").entries[1]

    assert(change.subject == "buy oat milk", change.subject)
    assert(change.path == "inbox/", change.path)
    assert(change.object_kind == "task", tostring(change.object_kind))
    assert(vim.deep_equal(change.fields, { "subject", "priority" }), vim.inspect(change.fields))
  end,

  ["leaves the field list empty on a create and on a delete"] = function()
    local model = status_model.build(fixture("full/status.json"), nil)

    assert(#section(model, "staged").entries[1].fields == 0)
    assert(section(model, "staged").entries[1].verb == "new")
    assert(section(model, "working").entries[2].verb == "removed")
  end,

  ["names every field dam's own changed_fields names"] = function()
    local function moved(before, after)
      return status_model.changed_fields(before, after)
    end

    assert(vim.deep_equal(moved({ subject = "a" }, { subject = "b" }), { "subject" }))
    assert(vim.deep_equal(moved({ body = "" }, { body = "x" }), { "body" }))
    assert(vim.deep_equal(moved({ path = "a/" }, { path = "b/" }), { "path" }))
    assert(vim.deep_equal(moved({ labels = { "a" } }, { labels = { "a", "b" } }), { "labels" }))
    assert(vim.deep_equal(moved({ depends = {} }, { depends = { "78b8950" } }), { "depends" }))
    assert(vim.deep_equal(moved({ reminders = {} }, { reminders = { "2026-09-25" } }), { "reminders" }))
    assert(vim.deep_equal(moved({ recurrence = nil }, { recurrence = "weekly" }), { "recurrence" }))
    assert(vim.deep_equal(moved({ task = { priority = 1 } }, { task = { priority = 2 } }), { "priority" }))
    assert(vim.deep_equal(moved({ task = { done = false } }, { task = { done = true } }), { "done" }))
    assert(vim.deep_equal(moved({ task = {} }, { task = { due = "2026-09-25" } }), { "due" }))
    assert(vim.deep_equal(moved({ task = {} }, { task = { deadline = "2026-09-30" } }), { "deadline" }))
    assert(vim.deep_equal(moved({ event = { start = "09:00" } }, { event = { start = "10:00" } }), { "start" }))
  end,

  ["carries a remote's unpushed count beside the name dam lists it under"] = function()
    local model = status_model.build(fixture("full/status.json"), fixture("full/remote.json"))
    local want = { { remote = "fake", commits = 1 }, { remote = "flaky", commits = 7 } }

    assert(vim.deep_equal(model.remotes, want), vim.inspect(model.remotes))
  end,

  ["builds a notice line out of the fields the notice actually carries"] = function()
    local model = status_model.build(fixture("full/status.json"), nil)
    local lines = vim.tbl_map(function(each)
      return each.text
    end, section(model, "notices").entries)

    local want = {
      "fake: 4aa4fab push failed upstream rejected the write: rate limited",
      "fedffd5 kind changed upstream",
      '5c82abc cancelled upstream "quarterly review"',
      'fake: fedffd5 removed upstream "from upstream"',
      "flaky: pull failed talking to the helper: the helper closed its output",
    }

    assert(vim.deep_equal(lines, want), vim.inspect(lines))
  end,
}
