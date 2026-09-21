-- Where in the code a task came from, as one line of its body.
--
-- The line is `<repository> <path>:<line>`, and `<path>:<line>` alone when the
-- file is in no repository. It is written to be read by a person on their
-- phone and parsed back by `gd`, in that order of importance.
--
-- THE PATH IS ALWAYS RELATIVE to the repository root, and a file outside a
-- repository goes out as its own name alone. A body syncs to a remote and to
-- every device that pulls it, so an absolute path would put the home directory
-- of the machine that captured it there.
--
-- Parsing a body back is parsing text a person can edit on their phone, so
-- every answer here is either a location or nil. Opening what one names is
-- `location_edit`, which is where the editor calls live.

local M = {}

--- The marker a task with a location carries in a list. Narrow enough not to
--- shift a line's other columns, and not a nerd-font glyph, so it draws in a
--- plain terminal font.
M.ICON = "⌖"

---@class damnit.Location
---@field repo string? the repository the file was in, when it was in one
---@field path string relative to that repository's root, or a bare file name
---@field line integer 1 or more

--- The one line a location is written as.
---@param location damnit.Location
---@return string
function M.describe(location)
  local where = ("%s:%d"):format(location.path, location.line)

  if location.repo then
    return location.repo .. " " .. where
  end

  return where
end

--- The location a body holds, or nil when no line of it is one.
---
--- Every line is tried rather than only the first, because a person who adds a
--- note to the task on their phone may well add it above the location.
---@param body string?
---@return damnit.Location? location
function M.parse(body)
  for line in tostring(body or ""):gmatch("[^\r\n]+") do
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

return M
