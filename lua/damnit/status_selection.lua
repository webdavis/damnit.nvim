local M = {}

function M.targets(rows, first, last)
  local picked, seen, section = {}, {}, nil

  local function take_if_change(row)
    if row and row.kind == "change" and row.oid and not seen[row.oid] then
      seen[row.oid] = true
      picked[#picked + 1] = row.oid
      section = section or row.section
    end
  end

  for lnum = first, last do
    local row = rows[lnum]

    if row and row.kind == "section" then
      section = section or row.section

      for _, each in ipairs(rows) do
        if each.section == row.section then
          take_if_change(each)
        end
      end
    else
      take_if_change(row)
    end
  end

  return { oids = picked, section = section }
end

return M
