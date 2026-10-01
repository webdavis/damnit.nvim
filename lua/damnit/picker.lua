local M = {}

local format = require("damnit.list_format")
local message = require("damnit.message")

local OID_DELIMITER = "\t"

local FIELDS_AFTER_THE_OID = "2.."

local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

function M.line(object)
  local parts = { text(object.subject) }
  format.append_badges(parts, object)

  local path = text(object.path)
  if path ~= "" then
    parts[#parts + 1] = path
  end

  return table.concat(parts, "  ")
end

function M.entries(objects)
  local entries = {}

  for _, object in ipairs(objects or {}) do
    entries[#entries + 1] = { oid = text(object.oid), text = M.line(object), object = object }
  end

  return entries
end

function M.open_entry(entry)
  require("damnit.task_buffer").open(entry.oid)
end

function M.complete_entry(entry)
  require("damnit.done").send(entry.object, false)
end

function M.chosen_oid(selected)
  local line = type(selected) == "table" and selected[1] or nil

  return type(line) == "string" and (line:match("^([^" .. OID_DELIMITER .. "]*)") or "") or ""
end

function M.fzf_lua()
  local wanted = require("damnit").options.picker

  if wanted ~= "auto" and wanted ~= "fzf-lua" and wanted ~= "select" then
    message.warn(("picker %q is not auto, fzf-lua or select; using auto"):format(tostring(wanted)))
    wanted = "auto"
  end

  if wanted == "select" then
    return nil
  end

  local ok, module = pcall(require, "fzf-lua")
  if ok then
    return module
  end

  if wanted == "fzf-lua" then
    message.warn("fzf-lua is not installed, so this is vim.ui.select")
  end

  return nil
end

local function with_fzf_lua(fzf_lua, entries, title)
  local lines, by_oid = {}, {}

  for _, entry in ipairs(entries) do
    lines[#lines + 1] = entry.oid .. OID_DELIMITER .. entry.text
    by_oid[entry.oid] = entry
  end

  local function act(handler)
    return function(selected)
      local entry = by_oid[M.chosen_oid(selected)]
      if entry then
        handler(entry)
      end
    end
  end

  fzf_lua.fzf_exec(lines, {
    prompt = title .. "> ",
    fzf_opts = { ["--delimiter"] = OID_DELIMITER, ["--with-nth"] = FIELDS_AFTER_THE_OID },
    actions = { ["enter"] = act(M.open_entry), ["ctrl-x"] = act(M.complete_entry) },
  })
end

local function with_ui_select(entries, title)
  vim.ui.select(entries, {
    prompt = title,
    format_item = function(entry)
      return entry.text
    end,
  }, function(entry)
    if entry then
      M.open_entry(entry)
    end
  end)
end

function M.show(entries, title)
  local fzf_lua = M.fzf_lua()

  if fzf_lua then
    return with_fzf_lua(fzf_lua, entries, title)
  end

  with_ui_select(entries, title)
end

local function search(spec)
  local list = require("damnit.list")
  local title = format.title(spec)

  list.fetch(spec, function(objects, err)
    if err then
      return message.report(err)
    end

    local entries = M.entries(objects)
    if #entries == 0 then
      return message.warn(("no objects in %s"):format(title))
    end

    M.show(entries, title)
  end)
end

function M.pick(name)
  local list = require("damnit.list")

  if name == nil or name == "" then
    return search(list.current_spec() or require("damnit.views").resolve(nil))
  end

  require("damnit.views").resolve_then(name, search)
end

return M
