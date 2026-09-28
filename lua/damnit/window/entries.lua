local M = {}

local function is_entry_of(sections, kinds, index, section_kind)
  return sections[index] == section_kind and kinds[index] ~= "section"
end

function M.line_of(buf, section_kind, nth)
  local sections = vim.b[buf].damnit_sections or {}
  local kinds = vim.b[buf].damnit_kinds or {}
  local seen = 0

  for index in ipairs(sections) do
    if is_entry_of(sections, kinds, index, section_kind) then
      seen = seen + 1

      if seen == nth then
        return index
      end
    end
  end

  local count_past_the_end_lands_on_the_last = seen > 0
  if count_past_the_end_lands_on_the_last then
    return M.line_of(buf, section_kind, seen)
  end

  return nil
end

function M.at_line(buf, lnum, model)
  local kinds = vim.b[buf].damnit_kinds or {}
  local sections = vim.b[buf].damnit_sections or {}

  if not model or kinds[lnum] == "section" or not sections[lnum] then
    return nil
  end

  for _, section in ipairs(model.sections) do
    if section.kind == sections[lnum] then
      local nth = 0

      for index = 1, lnum do
        if is_entry_of(sections, kinds, index, section.kind) then
          nth = nth + 1
        end
      end

      local entry = section.entries[nth]
      if entry then
        return { entry = entry, section = section }
      end
    end
  end

  return nil
end

return M
