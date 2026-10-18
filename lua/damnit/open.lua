local M = {}
local dam_object = require("damnit.object")

local diff = require("damnit.render.diff")
local scratch = require("damnit.scratch")
local status_model = require("damnit.status_model")
local verbs = require("damnit.dam.verbs")

local function set_field_lines(object)
  local lines = {}

  for _, field in ipairs(diff.set_fields(object)) do
    lines[#lines + 1] = ("%-10s %s"):format(field .. ":", diff.value(object, field))
  end

  return lines
end

function M.conflict(_, entry)
  local short = dam_object.short_oid(entry.oid)

  scratch.read_only(("damnit://conflict/%s/ours"):format(short), set_field_lines(entry.ours), "vsplit")
  scratch.read_only(("damnit://conflict/%s/theirs"):format(short), set_field_lines(entry.theirs), "vsplit")
end

local function commit_lines(commit)
  local lines = {
    ("commit %s  %s"):format(dam_object.short_oid(commit.id), tostring(commit.at or "")),
    ("  %s"):format(tostring(commit.message or "")),
    "",
  }

  for _, change in ipairs(commit.changes or {}) do
    local object = change.after or change.before or {}

    lines[#lines + 1] = ("  %-8s %s  %s"):format(
      status_model.VERBS[change.op] or tostring(change.op),
      dam_object.short_oid(change.oid),
      tostring(change.subject or object.subject or "")
    )
  end

  lines[#lines + 1] = ""

  return lines
end

local function newest(commits, count)
  return vim.list_slice(commits, 1, count)
end

function M.unpushed(app, entry)
  if (entry.commits or 0) == 0 then
    return app.say.warn("this remote has no commit on this line")
  end

  app.queue.submit({
    args = verbs.log(),
    label = "log",
    on_done = function(data, err)
      if err then
        return app.say.report(err)
      end

      local lines = {
        ("%s: the newest %d commit(s)"):format(entry.remote, entry.commits),
        ("%d unpushed; dam does not name which commits are unpushed"):format(entry.commits),
        "",
      }

      for _, commit in ipairs(newest((data or {}).commits or {}, entry.commits)) do
        vim.list_extend(lines, commit_lines(commit))
      end

      scratch.read_only(("damnit://unpushed/%s"):format(entry.remote), lines, "split")
    end,
  })
end

return M
