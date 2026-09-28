local M = {}

local DEADLINE_MS = 20000

local WAIT_INTERVAL_MS = 20

function M.settle(start)
  local boxed_answer = nil

  start(function(value, err)
    boxed_answer = { value = value, err = err }
  end)

  local finished = vim.wait(DEADLINE_MS, function()
    return boxed_answer ~= nil
  end, WAIT_INTERVAL_MS)

  if not finished then
    return false
  end

  return true, boxed_answer.value, boxed_answer.err
end

local function call(args)
  return M.settle(function(done)
    require("damnit.dam").call(args, nil, done)
  end)
end

local function nothing_to_speak_to(err)
  return err and (err.kind == "missing" or err.kind == "unsupported")
end

local function report_version_and_store()
  local dam = require("damnit.dam")
  local finished, data, err = call({ "ls", "--no-pull", "--json" })

  if not finished then
    vim.health.error(("dam did not answer within %d seconds"):format(DEADLINE_MS / 1000))

    return false
  end

  if nothing_to_speak_to(err) then
    vim.health.error(err.message)

    return false
  end

  local range = ("the supported range is >=%s <%s"):format(dam.MIN_VERSION, dam.MAX_VERSION)

  if dam.version then
    local first_dam_on_path = vim.fn.exepath("dam")
    vim.health.ok(("dam %s at %s, and %s"):format(dam.version, first_dam_on_path, range))
  else
    vim.health.warn(("dam --version printed something that is not a version, and %s"):format(range))
  end

  if err then
    vim.health.error(("the store did not answer: %s"):format(err.message))
  else
    local object_count = type(data.objects) == "table" and #data.objects or 0
    vim.health.ok(("the store answers, and holds %d objects"):format(object_count))
  end

  return true
end

local function report_paths()
  local options = require("damnit").options

  for _, flag in ipairs({ "store", "config" }) do
    local named = options[flag]
    local variable = "DAM_" .. flag:upper()
    local from_env = vim.env[variable]

    if type(named) == "string" and named ~= "" then
      vim.health.ok(("the %s is %s, from setup"):format(flag, named))
    elseif type(from_env) == "string" and from_env ~= "" then
      vim.health.ok(("the %s is %s, from %s"):format(flag, from_env, variable))
    else
      vim.health.ok(("the %s is dam's own, which no --%s overrides"):format(flag, flag))
    end
  end
end

local function report_remotes()
  local finished, data, err = call({ "remote", "list", "--json" })

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

local function report_filters()
  local finished, data, err = call({ "filter", "list", "--json" })

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

local function report_conflicts()
  local finished, data, err = call({ "status", "--json" })

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

local function report_views()
  local views = require("damnit").options.views or {}
  local declared = require("damnit.views").declared()

  if #declared == 0 then
    return vim.health.ok("no view is declared in setup")
  end

  for _, name in ipairs(declared) do
    local query = views[name]
    local finished, _, err = call({ "ls", query, "--no-pull", "--json" })

    if not finished then
      vim.health.error(("the view %s did not answer"):format(name))
    elseif err then
      vim.health.error(("the view %s runs %q, which dam refuses: %s"):format(name, query, err.message))
    else
      vim.health.ok(("the view %s runs %q"):format(name, query))
    end
  end
end

function M.check()
  vim.health.start("damnit.nvim")

  if not report_version_and_store() then
    return
  end

  report_paths()
  report_remotes()
  report_filters()
  report_conflicts()
  report_views()
end

return M
