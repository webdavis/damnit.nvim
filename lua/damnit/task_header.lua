local M = {}

local dam_object = require("damnit.object")
local text = dam_object.text

M.FENCE = "---"

function M.field_value(object, field)
  local group = object.kind == "event" and dam_object.event(object) or dam_object.task(object)

  if field == "labels" or field == "depends" then
    return table.concat(object[field] or {}, ", ")
  end

  if object[field] ~= nil then
    return text(object[field])
  end

  return text(group[field])
end

local function header_line_without_trailing_space(key, value)
  if value == "" then
    return key .. ":"
  end

  return ("%s: %s"):format(key, value)
end

function M.render(object)
  local lines = { M.FENCE }

  for _, key in ipairs(dam_object.header(object)) do
    lines[#lines + 1] = header_line_without_trailing_space(key, M.field_value(object, key))
  end

  lines[#lines + 1] = header_line_without_trailing_space("# reminders", table.concat(object.reminders or {}, ", "))

  if object.kind ~= "event" then
    lines[#lines + 1] = "# priority: 1 is highest"
  end

  lines[#lines + 1] = M.FENCE
  vim.list_extend(lines, vim.split(text(object.body), "\n", { plain = true }))

  return lines
end

function M.parse(lines)
  if lines[1] ~= M.FENCE then
    return nil, nil, ("the first line must be %s, the header fence"):format(M.FENCE)
  end

  local header, closed = {}, nil

  for index = 2, #lines do
    local line = lines[index]

    if line == M.FENCE then
      closed = index
      break
    end

    if not vim.startswith(line, "#") then
      local key, value = line:match("^(%l[%l_]*):%s*(.-)%s*$")

      if not key then
        return nil, nil, ("line %d is not a `key: value` header line: %s"):format(index, line)
      end

      if header[key] then
        return nil, nil, ("line %d repeats the field `%s`"):format(index, key)
      end

      header[key] = { value = value, line = index }
    end
  end

  if not closed then
    return nil, nil, ("the header has no closing %s fence"):format(M.FENCE)
  end

  return header, table.concat(vim.list_slice(lines, closed + 1), "\n")
end

function M.list_items(value)
  local items = {}

  for item in value:gmatch("[^,]+") do
    local trimmed = vim.trim(item)

    if trimmed ~= "" then
      items[#items + 1] = trimmed
    end
  end

  return items
end

return M
