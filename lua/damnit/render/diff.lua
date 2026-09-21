-- The inline field diff, as extmark virtual lines.
--
-- Virtual lines rather than inserted text: the buffer stays unmodifiable, every
-- other entry keeps its line number so a remembered cursor survives, and a
-- change here is a set of field pairs rather than a hunk of text.

local M = {}

local render = require("damnit.render")
local status_model = require("damnit.status_model")

--- The oids whose diff is open, per store, for the session.
---@type table<string, table<string, boolean>>
local open = {}

--- One field's value as text, with a dash for unset. A field lives either on the
--- object or inside its `task` or `event` table.
---@param object table?
---@param field string
---@return string
function M.value(object, field)
  if not object then
    return "-"
  end

  local value = object[field]

  if value == nil then
    value = (object.task or {})[field]
  end

  if value == nil then
    value = (object.event or {})[field]
  end

  if value == nil or value == vim.NIL or value == "" then
    return "-"
  end

  if type(value) == "table" then
    return #value > 0 and table.concat(value, ", ") or "-"
  end

  return tostring(value)
end

--- Every field one object has set, in dam's own order.
---@param object table?
---@return string[]
function M.set_fields(object)
  local names = {}

  for _, group in ipairs({ status_model.FIELDS, status_model.TASK_FIELDS, status_model.EVENT_FIELDS }) do
    for _, field in ipairs(group) do
      if M.value(object, field) ~= "-" then
        names[#names + 1] = field
      end
    end
  end

  return names
end

--- The virtual lines one change becomes.
---@param entry table
---@return table[][]
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

--- The oids whose diff is open in one store's window.
---@param key string
---@return table<string, boolean>
function M.open_set(key)
  open[key] = open[key] or {}

  return open[key]
end

--- Every change in one model, by oid.
---@param model damnit.Model?
---@return table<string, table>
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

--- Attach the open diffs to the lines a redraw just wrote.
---
--- An oid the status no longer carries draws nothing, which is how a diff is
--- forgotten.
---@param buf integer
---@param key string
---@param model damnit.Model?
function M.apply(buf, key, model)
  local wanted = M.open_set(key)
  if next(wanted) == nil then
    return
  end

  local changes = changes_of(model)

  for index, oid in ipairs(vim.b[buf].damnit_oids or {}) do
    local entry = oid and wanted[oid] and changes[oid]

    if entry then
      vim.api.nvim_buf_set_extmark(buf, render.NAMESPACE, index - 1, 0, {
        virt_lines = M.virt_lines(entry),
      })
    end
  end
end

return M
