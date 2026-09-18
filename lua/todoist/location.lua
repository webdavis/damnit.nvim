-- Where in the code a task came from, as one line of its description.
--
-- The line is `<repository> <path>:<line>`, and `<path>:<line>` alone when the
-- file is in no repository. It is written to be read by a person on their
-- phone and parsed back by `gd`, in that order of importance.
--
-- THE PATH IS ALWAYS RELATIVE to the repository root, and a file outside a
-- repository goes out as its own name alone. A description syncs to Todoist and
-- to every device signed into it, so an absolute path would put the home
-- directory of the machine that captured it there.
--
-- Parsing a description back is parsing text a person can edit on their phone,
-- so every answer here is either a location or nil, and `jump` reports what it
-- could not do rather than raising.

local M = {}

--- The marker a task with a location carries in a list. Narrow enough not to
--- shift a line's other columns, and not a nerd-font glyph, so it draws in a
--- plain terminal font.
M.ICON = "⌖"

---@class todoist.Location
---@field repo string? the repository the file was in, when it was in one
---@field path string relative to that repository's root, or a bare file name
---@field line integer 1 or more

---@param path string
---@return string? root normalized, when the path is inside a repository
local function repository_root(path)
  local root = vim.fs.root(path, ".git")

  return root and vim.fs.normalize(root) or nil
end

--- The location a buffer and a line are, or nil when there is nowhere to point.
---
--- A buffer with no name, a scratch buffer and a directory listing all answer
--- nil: none of them is a file with a line in it, and a capture from one simply
--- carries no location.
---@param buf integer? defaults to the current buffer
---@param line integer? defaults to the cursor's line
---@return todoist.Location? location
function M.of_buffer(buf, line)
  buf = buf or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1]

  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or vim.bo[buf].buftype ~= "" or vim.fn.isdirectory(name) == 1 then
    return nil
  end

  local path = vim.fs.normalize(name)
  local root = repository_root(path)

  if root and vim.startswith(path, root .. "/") then
    return { repo = vim.fs.basename(root), path = path:sub(#root + 2), line = line }
  end

  return { path = vim.fs.basename(path), line = line }
end

--- The one line a location is written as.
---@param location todoist.Location
---@return string
function M.describe(location)
  local where = ("%s:%d"):format(location.path, location.line)

  if location.repo then
    return location.repo .. " " .. where
  end

  return where
end

--- The location a description holds, or nil when no line of it is one.
---
--- Every line is tried rather than only the first, because a person who adds a
--- note to the task on their phone may well add it above the location.
---@param description string?
---@return todoist.Location? location
function M.parse(description)
  for line in tostring(description or ""):gmatch("[^\r\n]+") do
    local repo, path, number = line:match("^%s*(%S+)%s+(%S+):(%d+)%s*$")
    if not path then
      path, number = line:match("^%s*(%S+):(%d+)%s*$")
    end

    local parsed = tonumber(number)
    -- A bare number rules out prose like "Isaiah 40:31", which otherwise
    -- parses as a repository plus a path.
    if path and parsed and parsed >= 1 and not path:match("^%d+$") then
      return { repo = repo, path = path, line = parsed }
    end
  end

  return nil
end

---@param message string
---@return false
local function refuse(message)
  vim.notify("todoist.nvim: " .. message, vim.log.levels.WARN)

  return false
end

--- Open the file a location names and put the cursor on its line.
---
--- The path is resolved against the repository the editor is in, which is the
--- only base this plugin has: the description carries no absolute path, on
--- purpose. A location from another repository, a file that has since gone and
--- a line past the end of the file are each reported and none of them raises.
---@param location todoist.Location?
---@return boolean jumped
function M.jump(location)
  if not location then
    return refuse("this task has no location in its description")
  end

  local cwd = vim.fs.normalize(vim.uv.cwd() or ".")
  local base = repository_root(cwd) or cwd
  local here = vim.fs.basename(base)

  if location.repo and location.repo ~= here then
    return refuse(("this task points into %s, and %s is what is open here"):format(location.repo, here))
  end

  local path = vim.fs.joinpath(base, location.path)
  if vim.fn.filereadable(path) == 0 then
    return refuse(("there is no file at %s"):format(location.path))
  end

  require("todoist.sidebar").leave_fixed_window()
  vim.cmd.edit(vim.fn.fnameescape(path))

  local last = vim.api.nvim_buf_line_count(0)
  local line = math.min(location.line, last)
  vim.api.nvim_win_set_cursor(0, { line, 0 })

  if line ~= location.line then
    -- The file is open where it can be read; the line moved out from under the
    -- task, which is worth saying rather than landing silently.
    refuse(("%s has %d lines, so this is the last one"):format(location.path, last))
  end

  return true
end

return M
