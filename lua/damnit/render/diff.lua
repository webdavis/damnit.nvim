local M = {}

local render = require("damnit.render")
local dam_object = require("damnit.object")
local scratch = require("damnit.scratch")

local open_diffs_by_store = {}

local UNSET = "-"

function M.value(object, field)
  if not object then
    return UNSET
  end

  local value = object[field]

  if value == nil then
    value = dam_object.task(object)[field]
  end

  if value == nil then
    value = dam_object.event(object)[field]
  end

  if type(value) == "table" then
    return #value > 0 and table.concat(value, ", ") or UNSET
  end

  local shown = dam_object.text(value)

  return shown == "" and UNSET or shown
end

function M.set_fields(object)
  local names = {}

  for _, group in ipairs({ "object", "task", "event" }) do
    for _, field in ipairs(dam_object.FIELDS[group]) do
      if M.value(object, field) ~= UNSET then
        names[#names + 1] = field
      end
    end
  end

  return names
end

function M.virt_lines(entry)
  local fields = entry.fields or {}

  if entry.op == "create" then
    fields = M.set_fields(entry.after)
  elseif entry.op == "delete" then
    fields = M.set_fields(entry.before)
  end

  local lines = {}

  for _, field in ipairs(fields) do
    local chunks = { { ("           %-10s "):format(field), "DamFields" } }

    if entry.op == "create" then
      chunks[#chunks + 1] = { M.value(entry.after, field), "DamDiffNew" }
    elseif entry.op == "delete" then
      chunks[#chunks + 1] = { M.value(entry.before, field), "DamDiffOld" }
    else
      chunks[#chunks + 1] = { ("%-20s"):format(M.value(entry.before, field)), "DamDiffOld" }
      chunks[#chunks + 1] = { " ->  " }
      chunks[#chunks + 1] = { M.value(entry.after, field), "DamDiffNew" }
    end

    lines[#lines + 1] = chunks
  end

  return lines
end

function M.open_set(key)
  open_diffs_by_store[key] = open_diffs_by_store[key] or {}

  return open_diffs_by_store[key]
end

local function changes_of(model)
  local found = {}

  for _, section in ipairs((model or {}).sections or {}) do
    for _, entry in ipairs(section.entries) do
      if entry.kind == "change" then
        found[entry.oid] = entry
      end
    end
  end

  return found
end

function M.apply(buf, key, model)
  local wanted = M.open_set(key)
  if next(wanted) == nil then
    return
  end

  local changes = changes_of(model)

  for index, row in ipairs(scratch.rows(buf)) do
    local entry = row.oid and wanted[row.oid] and changes[row.oid]

    if entry then
      vim.api.nvim_buf_set_extmark(buf, render.NAMESPACE, index - 1, 0, {
        virt_lines = M.virt_lines(entry),
      })
    end
  end
end

return M
