-- The frontmatter, both directions, and the flags one edit becomes.
--
-- Both objects are the shape dam 0.2.0 writes, captured from `dam show --json`
-- against a store in a temporary directory.

local task_format = require("damnit.task_format")

local TASK = {
  oid = "c30414962aa4332b6e5dfc2e0360e2b328735efe",
  kind = "task",
  subject = "buy oat milk",
  body = "The kind in the grey carton.",
  path = "inbox/",
  labels = { "errand", "home" },
  depends = {},
  reminders = {},
  task = { done = false, priority = 1, due = "2026-09-25" },
}

local EVENT = {
  oid = "668db41d2c37143e7d1e37f45a5ba0bf5e028841",
  kind = "event",
  subject = "standup",
  body = "",
  path = "work/",
  labels = {},
  depends = {},
  reminders = {},
  event = {
    start = "2026-09-21T09:00:00-06:00[America/Denver]",
    ["end"] = "2026-09-21T09:15:00-06:00[America/Denver]",
    location = "room 3",
    attendees = {},
    status = "confirmed",
    transparency = "busy",
    visibility = "default",
    event_type = "default",
    attachments = {},
  },
}

---@param object table
---@param edits table<string, string>
---@return { edit: string[], move: string? }?
---@return { message: string, line: integer }?
local function after(object, edits)
  local lines = task_format.render(object)

  for index, line in ipairs(lines) do
    local key = line:match("^(%l[%l_]*):")
    if key and edits[key] then
      lines[index] = ("%s: %s"):format(key, edits[key])
    end
  end

  local header, body = task_format.parse(lines)

  return task_format.changes(object, header, body)
end

return {
  ["renders the header dam's way, priority first and reversed"] = function()
    local lines = task_format.render(TASK)

    assert(lines[1] == "---", lines[1])
    assert(vim.tbl_contains(lines, "subject: buy oat milk"), vim.inspect(lines))
    assert(vim.tbl_contains(lines, "path: inbox/"), vim.inspect(lines))
    assert(vim.tbl_contains(lines, "priority: 1"), vim.inspect(lines))
    assert(vim.tbl_contains(lines, "labels: errand, home"), vim.inspect(lines))
    assert(vim.tbl_contains(lines, "depends:"), "an empty field is `key:` with no trailing space")
    assert(vim.tbl_contains(lines, "# priority: 1 is highest"), vim.inspect(lines))
    assert(lines[#lines] == "The kind in the grey carton.", lines[#lines])
  end,

  ["sends only what changed"] = function()
    local changes = after(TASK, { subject = "buy the oat milk" })

    assert(vim.deep_equal(changes.edit, { "--subject", "buy the oat milk" }), vim.inspect(changes.edit))
  end,

  ["clears a due date with --no-due rather than an empty --due"] = function()
    local changes = after(TASK, { due = "" })

    assert(vim.deep_equal(changes.edit, { "--no-due" }), vim.inspect(changes.edit))
  end,

  ["diffs labels and depends as sets"] = function()
    local changes = after(TASK, { labels = "home, slow" })

    assert(vim.deep_equal(changes.edit, { "--label", "slow", "--unlabel", "errand" }), vim.inspect(changes.edit))
  end,

  ["moves into the container a changed path names"] = function()
    local changes = after(TASK, { path = "home/inbox/" })

    assert(changes.move == "home/", tostring(changes.move))
    assert(#changes.edit == 0, vim.inspect(changes.edit))
  end,

  ["sends a root object's new path whole, since it has no segment of its own"] = function()
    local rooted = vim.tbl_extend("force", TASK, { path = "" })
    local changes = after(rooted, { path = "home/errands/" })

    assert(changes.move == "home/errands/", tostring(changes.move))
  end,

  ["refuses a path that renames the object, which dam mv cannot do"] = function()
    local _, refused = after(TASK, { path = "home/errands/" })

    assert(refused.message:find("inbox", 1, true), refused.message)
    assert(refused.message:find("errands", 1, true), refused.message)
    assert(refused.line > 1, tostring(refused.line))
  end,

  ["refuses a path with an empty segment"] = function()
    local _, refused = after(TASK, { path = "home//inbox/" })

    assert(refused.message:find("empty segment", 1, true), refused.message)
  end,

  ["refuses an empty subject and a priority outside dam's range, on the right line"] = function()
    local _, refused = after(TASK, { subject = "" })
    assert(refused.message:find("subject", 1, true), refused.message)
    assert(refused.line > 1, tostring(refused.line))

    local _, bad = after(TASK, { priority = "9" })
    assert(bad.message:find("1, 2, 3 or 4", 1, true), bad.message)
    assert(bad.message:find("1 is the most urgent", 1, true), bad.message)
  end,

  ["refuses a depends entry too short to be an oid prefix"] = function()
    local _, refused = after(TASK, { depends = "abc" })

    assert(refused.message:find("four", 1, true), refused.message)
  end,

  ["reads an event's own fields and leaves out the ones dam does not keep"] = function()
    local lines = task_format.render(EVENT)

    assert(vim.tbl_contains(lines, "start: 2026-09-21T09:00:00-06:00[America/Denver]"), vim.inspect(lines))
    assert(vim.tbl_contains(lines, "location: room 3"), vim.inspect(lines))
    assert(not vim.tbl_contains(lines, "priority: 1"), "an event has no priority")

    -- dam 0.2.0 keeps no timezone field and `dam edit` takes no --timezone: the
    -- zone rides inside start and end.
    for _, line in ipairs(lines) do
      assert(not vim.startswith(line, "timezone:"), line)
    end
  end,

  ["sends an event's changed end through its own flag"] = function()
    local changes = after(EVENT, { ["end"] = "2026-09-21T09:30:00-06:00[America/Denver]" })

    assert(
      vim.deep_equal(changes.edit, { "--end", "2026-09-21T09:30:00-06:00[America/Denver]" }),
      vim.inspect(changes.edit)
    )
  end,
}
