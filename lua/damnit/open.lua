-- The read-only buffers the status window opens.
--
-- Each is a scratch buffer built from a document dam already answered with, so
-- none of them is a second view of the store that could disagree with the one
-- the window drew.

local M = {}

local diff = require("damnit.render.diff")
local message = require("damnit.message")
local status_model = require("damnit.status_model")

---@param name string
---@param lines string[]
---@return integer buf
local function read_only(name, lines)
  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.api.nvim_win_set_buf(0, buf)

  return buf
end

--- One wire object as its set fields, one per line.
---@param object table?
---@return string[]
local function object_lines(object)
  local lines = {}

  for _, field in ipairs(diff.set_fields(object)) do
    lines[#lines + 1] = ("%-10s %s"):format(field .. ":", diff.value(object, field))
  end

  return lines
end

--- Both sides of a conflict, ours on the left and theirs on the right.
---
--- `dam status` carries the two objects in full, so this needs no call.
---@param entry table
function M.conflict(entry)
  local short = entry.oid:sub(1, 7)

  vim.cmd("vsplit")
  read_only(("damnit://conflict/%s/ours"):format(short), object_lines(entry.ours))

  vim.cmd("vsplit")
  read_only(("damnit://conflict/%s/theirs"):format(short), object_lines(entry.theirs))
end

---@param commit table
---@return string[]
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

--- One remote's newest commits, with what the status says it is behind by.
---
--- dam counts a remote's unpushed commits rather than naming them, so this
--- shows the newest ones the log holds and says so. They are not the unpushed
--- set: a push marks a later commit pushed while an earlier one whose objects
--- the helper did not answer stays behind. Naming them is a dam change.
---@param entry table the Unpushed row under the cursor
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

      for index, commit in ipairs((data or {}).commits or {}) do
        if index > entry.commits then
          break
        end

        vim.list_extend(lines, commit_lines(commit))
      end

      read_only(("damnit://unpushed/%s"):format(entry.remote), lines)
    end,
  })
end

return M
