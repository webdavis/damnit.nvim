local M = {}

M.ICON = "⌖"

local function is_verse_chapter(path)
  return path:match("^%d+$") ~= nil
end

function M.describe(location)
  local where = ("%s:%d"):format(location.path, location.line)

  if location.repo then
    return location.repo .. " " .. where
  end

  return where
end

function M.parse(body)
  for line in tostring(body or ""):gmatch("[^\r\n]+") do
    local repo, path, number = line:match("^%s*(%S+)%s+(%S+):(%d+)%s*$")
    if not path then
      path, number = line:match("^%s*(%S+):(%d+)%s*$")
    end

    local parsed = tonumber(number)
    if path and parsed and parsed >= 1 and not is_verse_chapter(path) then
      return { repo = repo, path = path, line = parsed }
    end
  end

  return nil
end

return M
