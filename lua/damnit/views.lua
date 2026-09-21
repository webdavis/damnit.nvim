-- A view is a name and a dam query.
--
-- Two sources, merged, with this plugin's own table winning a collision: the
-- `views` option, and dam's saved filters, which dam resolves when `dam ls` is
-- given a bare word. A name declared in dam's own config therefore works in the
-- editor, in a terminal and in a herdr pane with one declaration.

local M = {}

local message = require("damnit.message")

---@class damnit.ListSpec
---@field title string what the buffer's first line calls it
---@field query string? the dam query, or nil for every open task
---@field probing boolean? true when the query is a bare name dam has yet to judge

--- Names dam refused this session, so the second attempt costs no call.
---@type table<string, boolean>
local unknown = {}

--- The view names declared in `setup`, sorted.
---@return string[]
function M.declared()
  local names = vim.tbl_keys(require("damnit").options.views or {})
  table.sort(names)

  return names
end

--- Remember that dam does not know this name either.
---@param name string
function M.forget_filter(name)
  unknown[name] = true
end

---@param name string
local function refuse(name)
  local declared = M.declared()
  local known = #declared > 0 and ("declared views are " .. table.concat(declared, ", "))
    or "no views are declared in setup"

  message.fail(("there is no view named %q. %s"):format(name, known))
end

--- The spec a view name means, or nil after saying there is no such view.
---@param name string?
---@return damnit.ListSpec?
function M.resolve(name)
  if name == nil or name == "" then
    return { title = "all open tasks" }
  end

  local query = (require("damnit").options.views or {})[name]
  if type(query) == "string" then
    return { title = name, query = query }
  end

  if unknown[name] then
    refuse(name)

    return nil
  end

  return { title = name, query = name, probing = true }
end

--- Forget every name dam refused. Specs call it between cases; nothing in the
--- plugin does.
function M.reset()
  unknown = {}
end

--- The `ls` argv tail one spec becomes.
---@param spec damnit.ListSpec
---@return string[]
function M.query_args(spec)
  if spec.query == nil or spec.query == "" then
    return { "ls", "--json" }
  end

  return { "ls", spec.query, "--json" }
end

return M
