local M = {}

---@class damnit.ListSpec
---@field title string
---@field query? string
---@field flat? boolean

---@type damnit.ListSpec
M.COMPLETED = { title = "completed", query = "done", flat = true }

local one_read = require("damnit.one_read")
local verbs = require("damnit.dam.verbs")

local dam_filters_this_session = nil
local the_filter_list = one_read.new()

local function declared_views(app)
  return app.options.views or {}
end

function M.declared(app)
  local names = vim.tbl_keys(declared_views(app))
  table.sort(names)

  return names
end

function M.known(app)
  local names = M.declared(app)

  for _, name in ipairs(dam_filters_this_session or {}) do
    if not declared_views(app)[name] then
      names[#names + 1] = name
    end
  end
  table.sort(names)

  return names
end

function M.load(app, on_loaded)
  on_loaded = on_loaded or function() end

  if dam_filters_this_session then
    return on_loaded()
  end

  the_filter_list.wait(function(err)
    if not err then
      on_loaded()
    end
  end, function()
    app.queue.submit({
      args = verbs.filter_list(),
      label = "filter list",
      on_done = function(data, err)
        if err then
          app.say.report(err)
        else
          dam_filters_this_session = {}
          for _, filter in ipairs(type(data.filters) == "table" and data.filters or {}) do
            dam_filters_this_session[#dam_filters_this_session + 1] = tostring(filter.name)
          end
        end

        the_filter_list.settle(err)
      end,
    })
  end)
end

local function refuse(app, name)
  local declared = M.declared(app)
  local known = #declared > 0 and ("declared views are " .. table.concat(declared, ", "))
    or "no views are declared in setup"

  if dam_filters_this_session and #dam_filters_this_session > 0 then
    known = known .. "; dam's saved filters are " .. table.concat(dam_filters_this_session, ", ")
  end

  app.say.fail(("there is no view named %q; %s"):format(name, known))
end

---@return damnit.ListSpec?
function M.resolve(app, name)
  if name == nil or name == "" then
    return { title = "all open tasks" }
  end

  local query = declared_views(app)[name]
  if type(query) == "string" then
    return { title = name, query = query }
  end

  if vim.tbl_contains(dam_filters_this_session or {}, name) then
    return { title = name, query = name }
  end

  refuse(app, name)
end

---@param on_spec fun(spec: damnit.ListSpec): any
function M.resolve_then(app, name, on_spec)
  local needs_dams_list = name ~= nil and name ~= "" and type(declared_views(app)[name]) ~= "string"

  if not needs_dams_list then
    return on_spec(M.resolve(app, name))
  end

  M.load(app, function()
    local spec = M.resolve(app, name)

    if spec then
      on_spec(spec)
    end
  end)
end

function M.reset()
  dam_filters_this_session = nil
  the_filter_list = one_read.new()
end

---@param spec damnit.ListSpec
function M.query_args(spec)
  if spec.query == nil or spec.query == "" then
    return verbs.ls("!done")
  end

  return verbs.ls(spec.query)
end

return M
