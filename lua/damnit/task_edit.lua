local M = {}

local dam_object = require("damnit.object")
local task_check = require("damnit.task_check")
local task_header = require("damnit.task_header")
local text = dam_object.text

local CANNOT_BE_CLEARED = false

M.FLAGS = {
  subject = { set = "--subject", clear = CANNOT_BE_CLEARED },
  priority = { set = "-p", clear = CANNOT_BE_CLEARED },
  due = { set = "--due", clear = "--no-due" },
  deadline = { set = "--deadline", clear = "--no-deadline" },
  recurrence = { set = "--recurrence", clear = "--no-recurrence" },
  start = { set = "--start", clear = CANNOT_BE_CLEARED },
  ["end"] = { set = "--end", clear = CANNOT_BE_CLEARED },
  location = { set = "--location", clear = "--no-location" },
}

local function set_diff(wanted, held)
  local have, want = {}, {}

  for _, item in ipairs(held) do
    have[item] = true
  end
  for _, item in ipairs(wanted) do
    want[item] = true
  end

  local added, removed = {}, {}

  for _, item in ipairs(wanted) do
    if not have[item] then
      added[#added + 1] = item
    end
  end
  for _, item in ipairs(held) do
    if not want[item] then
      removed[#removed + 1] = item
    end
  end

  return added, removed
end

local function append_flags(object, key, entry, edit)
  if key == "done" then
    if entry.value == "false" then
      edit[#edit + 1] = "--undone"

      return nil
    end

    return task_check.refuse(
      "`done` only takes false here, which sends --undone; complete an object with x, or dam done",
      entry
    )
  end

  if key == "labels" or key == "depends" then
    local added, removed = set_diff(task_header.list_items(entry.value), object[key] or {})
    local set = key == "labels" and "--label" or "--depends"
    local clear = key == "labels" and "--unlabel" or "--undepends"

    for _, item in ipairs(added) do
      vim.list_extend(edit, { set, item })
    end
    for _, item in ipairs(removed) do
      vim.list_extend(edit, { clear, item })
    end

    return nil
  end

  if entry.value == "" then
    local clear = M.FLAGS[key].clear

    if not clear then
      return task_check.refuse(("`%s` cannot be cleared"):format(key), entry)
    end

    edit[#edit + 1] = clear

    return nil
  end

  vim.list_extend(edit, { M.FLAGS[key].set, entry.value })

  return nil
end

function M.changes(object, header, body)
  local refusal = task_check.refusal_in(object, header)
  if refusal then
    return nil, refusal
  end

  local edit, move = {}, nil

  local path = header.path
  if path and path.value ~= task_header.field_value(object, "path") then
    if path.value:find("//", 1, true) then
      return nil, task_check.refuse("`path` has an empty segment", path)
    end

    move = path.value
  end

  for _, key in ipairs(dam_object.header(object)) do
    local entry = header[key]

    if entry and key ~= "path" and entry.value ~= task_header.field_value(object, key) then
      local refused = append_flags(object, key, entry, edit)
      if refused then
        return nil, refused
      end
    end
  end

  if body ~= text(object.body) then
    vim.list_extend(edit, { "--body", body })
  end

  return { edit = edit, move = move }
end

return M
