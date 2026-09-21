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

  ["names an update's changed fields in dam's own order"] = function()
    local model = status_model.build(fixture("full/status.json"), nil)
    local change = section(model, "working").entries[1]

    assert(change.verb == "changed", change.verb)
    assert(change.oid == "78b8950b02735107aa608659dcf19f6f50adfeb1", change.oid)
    assert(vim.deep_equal(change.fields, { "subject", "labels", "due" }), vim.inspect(change.fields))
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

  ["carries a remote's unpushed count beside its name"] = function()
    local model = status_model.build(fixture("full/status.json"), fixture("full/remote.json"))

    assert(vim.deep_equal(model.remotes, { { remote = "todoist", commits = 1 } }), vim.inspect(model.remotes))
  end,

  ["builds a notice line out of the fields the notice actually carries"] = function()
    local model = status_model.build(fixture("full/status.json"), nil)
    local notice = section(model, "notices").entries[1]

    assert(notice.text == "todoist: c1d2e3f removed upstream", notice.text)
  end,
}
