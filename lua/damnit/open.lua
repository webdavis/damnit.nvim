local M = {}

local diff = require("damnit.render.diff")
local message = require("damnit.message")
local scratch = require("damnit.scratch")
local status_model = require("damnit.status_model")

local function configure(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
end

local function read_only(name, lines, split)
  local buf = scratch.named(name, configure)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  if not scratch.focus(buf) then
    vim.cmd(split)
    vim.api.nvim_win_set_buf(0, buf)
  end

  return buf
end

local function set_field_lines(object)
  local lines = {}

  for _, field in ipairs(diff.set_fields(object)) do
    lines[#lines + 1] = ("%-10s %s"):format(field .. ":", diff.value(object, field))
  end

  return lines
end

function M.conflict(entry)
  local short = entry.oid:sub(1, 7)

  read_only(("damnit://conflict/%s/ours"):format(short), set_field_lines(entry.ours), "vsplit")
  read_only(("damnit://conflict/%s/theirs"):format(short), set_field_lines(entry.theirs), "vsplit")
end

local function commit_lines(commit)
  local lines = {
    ("commit %s  %s"):format(tostring(commit.id):sub(1, 7), tostring(commit.at or "")),
    ("  %s"):format(tostring(commit.message or "")),
    "",
  }

  for _, change in ipairs(commit.changes or {}) do
    local object = change.after or change.before or {}

    lines[#lines + 1] = ("  %-8s %s  %s"):format(
      status_model.VERBS[change.op] or tostring(change.op),
      tostring(change.oid):sub(1, 7),
      tostring(change.subject or object.subject or "")
    )
  end

  lines[#lines + 1] = ""

  return lines
end

local function newest(commits, count)
  return vim.list_slice(commits, 1, count)
end

function M.unpushed(entry)
  if (entry.commits or 0) == 0 then
    return message.warn("this remote has no commit on this line")
  end

  require("damnit.queue").submit({
    args = { "log", "--json" },
    label = "log",
    on_done = function(data, err)
      if err then
        return message.report(err)
      end

      local lines = {
        ("%s: the newest %d commit(s)"):format(entry.remote, entry.commits),
        ("%d unpushed; dam does not name which commits are unpushed"):format(entry.commits),
        "",
      }

      for _, commit in ipairs(newest((data or {}).commits or {}, entry.commits)) do
        vim.list_extend(lines, commit_lines(commit))
      end

      read_only(("damnit://unpushed/%s"):format(entry.remote), lines, "split")
    end,
  })
end

return M
