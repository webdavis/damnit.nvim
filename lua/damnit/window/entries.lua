local M = {}

local scratch = require("damnit.scratch")

function M.line_of(buf, section_kind, nth)
  local last = nil

  for lnum, row in ipairs(scratch.rows(buf)) do
    if row.section == section_kind and row.nth then
      if row.nth == nth then
        return lnum
      end

      last = lnum
    end
  end

  return last
end

function M.place(buf, lnum)
  local row = scratch.row(buf, lnum)

  if not row or not row.nth then
    return nil
  end

  return { section = row.section, nth = row.nth }
end

function M.at_line(buf, lnum, model)
  local row = scratch.row(buf, lnum)

  if not model or not row or not row.entry then
    return nil
  end

  for _, section in ipairs(model.sections) do
    if section.kind == row.section then
      return { entry = row.entry, section = section }
    end
  end

  return nil
end

return M
