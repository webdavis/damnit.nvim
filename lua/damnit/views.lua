local M = {}

local message = require("damnit.message")

local refused_by_dam_this_session = {}

function M.declared()
  local names = vim.tbl_keys(require("damnit").options.views or {})
  table.sort(names)

  return names
end

function M.forget_filter(name)
  refused_by_dam_this_session[name] = true
end

local function refuse(name)
  local declared = M.declared()
  local known = #declared > 0 and ("declared views are " .. table.concat(declared, ", "))
    or "no views are declared in setup"

  message.fail(("there is no view named %q. %s"):format(name, known))
end

function M.resolve(name)
  if name == nil or name == "" then
    return { title = "all open tasks" }
  end

  local query = (require("damnit").options.views or {})[name]
  if type(query) == "string" then
    return { title = name, query = query }
  end

  if refused_by_dam_this_session[name] then
    refuse(name)

    return nil
  end

  return { title = name, query = name, probing = true }
end

function M.reset()
  refused_by_dam_this_session = {}
end

function M.query_args(spec)
  if spec.query == nil or spec.query == "" then
    return { "ls", "--json" }
  end

  return { "ls", spec.query, "--json" }
end

return M
