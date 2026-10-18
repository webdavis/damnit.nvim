local dam_object = require("damnit.object")

local function same(got, want)
  assert(vim.deep_equal(got, want), vim.inspect(got))
end

return {
  ["text reads nil and json null as empty"] = function()
    same({ dam_object.text(nil), dam_object.text(vim.NIL), dam_object.text(4), dam_object.text(false) }, {
      "",
      "",
      "4",
      "false",
    })
  end,

  ["present turns json null into nil and keeps everything else"] = function()
    same({ dam_object.present(vim.NIL), dam_object.present(false), dam_object.present("x") }, { nil, false, "x" })
  end,

  ["a short oid is its first seven characters"] = function()
    same(dam_object.short_oid("badb4903b653809e591c31118004e07de7c8183c"), "badb490")
    same(dam_object.short_oid(vim.NIL), "")
  end,

  ["task and event read an absent or null group as empty"] = function()
    same(dam_object.task({ task = { due = "2026-10-01" } }), { due = "2026-10-01" })
    same(dam_object.task({ task = vim.NIL }), {})
    same(dam_object.event({}), {})
  end,

  ["the fields fall into the object, task and event groups"] = function()
    same(dam_object.FIELDS, {
      object = { "subject", "body", "path", "labels", "depends", "reminders", "recurrence" },
      task = { "done", "priority", "due", "deadline" },
      event = { "start", "end", "timezone", "location", "transparency" },
    })
  end,

  ["a task header and an event header list their fields in buffer order"] = function()
    same(
      dam_object.header({ kind = "task" }),
      { "subject", "path", "done", "priority", "due", "deadline", "labels", "depends", "recurrence" }
    )
    same(dam_object.header({ kind = "event" }), { "subject", "path", "start", "end", "location", "labels", "depends" })
  end,
}
