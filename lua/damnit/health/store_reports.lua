local M = {}

local call = require("damnit.health.ask").call
local verbs = require("damnit.dam.verbs")
local views = require("damnit.views")

function M.remotes(app)
  local finished, data, err = call(app, verbs.remote_list())

  if not finished or err then
    return vim.health.warn(("the remotes could not be read: %s"):format(err and err.message or "dam did not answer"))
  end

  local remotes = type(data.remotes) == "table" and data.remotes or {}

  if #remotes == 0 then
    return vim.health.ok("no remote is configured, so nothing pushes or pulls")
  end

  for _, remote in ipairs(remotes) do
    local parts = {
      ("the remote %s speaks through the %s helper at %s"):format(
        tostring(remote.name),
        tostring(remote.helper),
        tostring(remote.url)
      ),
    }

    if type(remote.path) == "string" then
      parts[#parts + 1] = ("narrowed to %s"):format(remote.path)
    end

    if tonumber(remote.stale_seconds) then
      parts[#parts + 1] = ("stale after %ds, so a read may pull it first"):format(remote.stale_seconds)
    end

    vim.health.ok(table.concat(parts, ", "))
  end
end

function M.filters(app)
  local finished, data, err = call(app, verbs.filter_list())

  if not finished or err then
    return vim.health.warn(
      ("dam's saved filters could not be read: %s"):format(err and err.message or "dam did not answer")
    )
  end

  local filters = type(data.filters) == "table" and data.filters or {}

  if #filters == 0 then
    return vim.health.ok("dam declares no saved filter")
  end

  local names = {}
  for _, filter in ipairs(filters) do
    names[#names + 1] = tostring(filter.name)
  end

  vim.health.ok(("dam's own saved filters are %s, and :Dam list takes any of them"):format(table.concat(names, ", ")))
end

function M.conflicts(app)
  local finished, data, err = call(app, verbs.status())

  if not finished or err then
    return vim.health.warn(("the status could not be read: %s"):format(err and err.message or "dam did not answer"))
  end

  local conflicts = type(data.conflicts) == "table" and #data.conflicts or 0

  if conflicts == 0 then
    return vim.health.ok("no conflict is waiting")
  end

  vim.health.warn(
    ("%d object%s in conflict; co and ct settle one in the status window"):format(
      conflicts,
      conflicts == 1 and " is" or "s are"
    )
  )
end

function M.views(app)
  local queries = app.options.views or {}
  local declared = views.declared(app)

  if #declared == 0 then
    return vim.health.ok("no view is declared in setup")
  end

  for _, name in ipairs(declared) do
    local query = queries[name]
    local finished, _, err = call(app, verbs.ls(query, true))

    if not finished then
      vim.health.error(("the view %s did not answer"):format(name))
    elseif err then
      vim.health.error(("the view %s runs %q, which dam refuses: %s"):format(name, query, err.message))
    else
      vim.health.ok(("the view %s runs %q"):format(name, query))
    end
  end
end

return M
