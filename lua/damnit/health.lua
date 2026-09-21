-- `:checkhealth damnit`
--
-- Six reports, in the order they can fail: is there a dam this plugin speaks
-- to, what does the store hold, where is the plugin pointing it, what can it
-- reach, what is waiting, and which of the declared views will it actually run.
--
-- The first of those is the handshake's own answer rather than a second probe:
-- a spawn against a binary that is not there throws at once, so the handshake
-- already reports the absence, with the install line, without waiting.
--
-- Nothing here reports anything about a credential. dam resolves its own and
-- hands none back, so there is nothing to print and nothing to redact.

local M = {}

--- The check is allowed to be slow: it runs because the operator asked for a
--- report, and each of its calls is a process.
local DEADLINE_MS = 20000

--- Run an async call to completion inside the synchronous health check.
---
--- `vim.wait` keeps the event loop turning, which is what lets the spawn's own
--- callback and the `vim.schedule` behind it run here at all. This is the one
--- place in the plugin where waiting is correct.
---
--- The answer is carried as a table rather than as varargs, because a list
--- holding a nil has no reliable length in Lua.
---@param start fun(done: fun(value: any?, err: any?))
---@return boolean finished
---@return any? value
---@return any? err
function M.settle(start)
  local answer = nil

  start(function(value, err)
    answer = { value = value, err = err }
  end)

  local finished = vim.wait(DEADLINE_MS, function()
    return answer ~= nil
  end, 20)

  if not finished then
    return false
  end

  return true, answer.value, answer.err
end

--- One dam call, run to completion.
---@param args string[]
---@return boolean finished
---@return table? data
---@return damnit.Error? err
local function call(args)
  return M.settle(function(done)
    require("damnit.dam").call(args, nil, done)
  end)
end

--- The version and the store, off one `ls`: the handshake this call runs is
--- what reads the version, and the same answer carries the object count.
---@return boolean ready whether the remaining reports are worth running
local function report_version_and_store()
  local dam = require("damnit.dam")
  local finished, data, err = call({ "ls", "--no-pull", "--json" })

  if not finished then
    vim.health.error(("dam did not answer within %d seconds"):format(DEADLINE_MS / 1000))

    return false
  end

  -- A dam this plugin will not speak to, or is not there, is the end of the
  -- report: every check below would refuse for that reason and say so five
  -- more times.
  if err and (err.kind == "missing" or err.kind == "unsupported") then
    vim.health.error(err.message)

    return false
  end

  local range = ("the supported range is >=%s <%s"):format(dam.MIN_VERSION, dam.MAX_VERSION)

  if dam.version then
    vim.health.ok(("dam %s, and %s"):format(dam.version, range))
  else
    vim.health.warn(("dam --version printed something that is not a version, and %s"):format(range))
  end

  if err then
    vim.health.error(("the store did not answer: %s"):format(err.message))
  else
    local objects = type(data.objects) == "table" and #data.objects or 0
    vim.health.ok(("the store answers, and holds %d objects"):format(objects))
  end

  return true
end

--- Where the plugin points dam. dam prints neither its store nor its config
--- path, so this reports what it is told rather than what it decided.
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

--- One line per configured remote, naming the helper that speaks to it.
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
    vim.health.ok(("the remote %s speaks through the %s helper"):format(tostring(remote.name), tostring(remote.helper)))
  end
end

--- dam's own saved filters, which `:Dam list` takes by name alongside the
--- views `setup` declares.
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

--- What is waiting for a hand, which is the one thing a report can tell you
--- that you would otherwise only find by opening the window.
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

--- Every view `setup` declares, run against dam so a query it refuses is found
--- here rather than the first time a key is pressed.
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
