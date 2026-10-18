local M = {}

local text = require("damnit.object").text
local done = require("damnit.done")
local format = require("damnit.list_format")
local list = require("damnit.list")
local task_buffer = require("damnit.task_buffer")
local views = require("damnit.views")

local OID_DELIMITER = "\t"

local FIELDS_AFTER_THE_OID = "2.."

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

function M.open_entry(app, entry)
  task_buffer.open(app, entry.oid)
end

function M.complete_entry(app, entry)
  done.send(app, entry.object)
end

function M.chosen_oid(selected)
  local line = type(selected) == "table" and selected[1] or nil

  return type(line) == "string" and (line:match("^([^" .. OID_DELIMITER .. "]*)") or "") or ""
end

function M.fzf_lua(app)
  local wanted = app.options.picker

  if wanted ~= "auto" and wanted ~= "fzf-lua" and wanted ~= "select" then
    app.say.warn(("picker %q is not auto, fzf-lua or select; using auto"):format(tostring(wanted)))
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
    app.say.warn("fzf-lua is not installed, so this is vim.ui.select")
  end

  return nil
end

local function with_fzf_lua(app, fzf_lua, entries, title)
  local lines, by_oid = {}, {}

  for _, entry in ipairs(entries) do
    lines[#lines + 1] = entry.oid .. OID_DELIMITER .. entry.text
    by_oid[entry.oid] = entry
  end

  local function act(handler)
    return function(selected)
      local entry = by_oid[M.chosen_oid(selected)]
      if entry then
        handler(app, entry)
      end
    end
  end

  fzf_lua.fzf_exec(lines, {
    prompt = title .. "> ",
    fzf_opts = { ["--delimiter"] = OID_DELIMITER, ["--with-nth"] = FIELDS_AFTER_THE_OID },
    actions = { ["enter"] = act(M.open_entry), ["ctrl-x"] = act(M.complete_entry) },
  })
end

local function with_ui_select(app, entries, title)
  vim.ui.select(entries, {
    prompt = title,
    format_item = function(entry)
      return entry.text
    end,
  }, function(entry)
    if entry then
      M.open_entry(app, entry)
    end
  end)
end

function M.show(app, entries, title)
  local fzf_lua = M.fzf_lua(app)

  if fzf_lua then
    return with_fzf_lua(app, fzf_lua, entries, title)
  end

  with_ui_select(app, entries, title)
end

local function search(app, spec)
  local title = format.title(spec)

  list.fetch(app, spec, function(objects, err)
    if err then
      return app.say.report(err)
    end

    local entries = M.entries(objects)
    if #entries == 0 then
      return app.say.warn(("no objects in %s"):format(title))
    end

    M.show(app, entries, title)
  end)
end

function M.pick(app, name)
  if name == nil or name == "" then
    return search(app, list.current_spec() or views.resolve(app, nil))
  end

  views.resolve_then(app, name, function(spec)
    search(app, spec)
  end)
end

return M
