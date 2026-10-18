local M = {}

local OVERRUN_GAP = " "

function M.new()
  local parts, marks, bytes, display = {}, {}, 0, 0

  local function add(text, group, pad_to_display_column)
    text = tostring(text)

    if group and #text > 0 then
      marks[#marks + 1] = { col = bytes, length = #text, group = group }
    end

    parts[#parts + 1] = text
    bytes = bytes + #text
    display = display + vim.fn.strdisplaywidth(text)

    if pad_to_display_column then
      local fill = ""

      if display < pad_to_display_column then
        fill = (" "):rep(pad_to_display_column - display)
      elseif display > pad_to_display_column then
        fill = OVERRUN_GAP
      end

      parts[#parts + 1] = fill
      bytes = bytes + #fill
      display = display + #fill
    end
  end

  return {
    add = add,
    line = function(kind, oid)
      return { text = (table.concat(parts):gsub("%s+$", "")), kind = kind, oid = oid, marks = marks }
    end,
  }
end

return M
