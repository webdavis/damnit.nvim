-- `:checkhealth todoist`
--
-- Three questions, in the order they can fail: is there a curl to run, does the
-- configured source produce a token, and does the API accept it. The third is
-- the only one worth asking, and the only way to ask it is to make a request,
-- so the check makes the cheapest one there is.
--
-- What it reports about the token is that it resolved. Not its value, not its
-- length, not its first characters, not which vault entry it came out of.

local M = {}

--- The check is allowed to be slow: it runs because the operator asked for a
--- report, and it has a vault command and a round trip to wait for.
local DEADLINE_MS = 20000

--- Run an async call to completion inside the synchronous health check.
---
--- `vim.wait` keeps the event loop turning, which is what lets the `vim.system`
--- callback and the `vim.schedule` behind it run here at all.
--- Both callers are answered with a value and an error, one of which is nil,
--- so the pair is carried explicitly rather than as varargs: a list holding a
--- nil has no reliable length in Lua.
---@param start fun(done: fun(value: any?, err: any?))
---@return boolean finished
---@return any? value
---@return any? err
local function settle(start)
  local answer = nil

  start(function(value, err)
    answer = { value = value, err = err }
  end)

  local finished = vim.wait(DEADLINE_MS, function()
    return answer ~= nil
  end, 50)

  if not finished then
    return false
  end

  return true, answer.value, answer.err
end

local function check_curl(options)
  local curl = vim.fs.normalize(options.curl)

  if vim.fn.executable(curl) ~= 1 then
    vim.health.error(("curl was not found as %s"):format(curl), {
      "Install curl, or set the curl option to where it lives.",
    })
    return false
  end

  vim.health.ok(("curl is %s"):format(curl))

  return true
end

local function check_token_source(options)
  if options.token then
    vim.health.warn("the token is a value in the configuration", {
      "Anyone who can read the configuration file can read the token.",
      "Prefer token_command, which names a vault or keychain call instead.",
    })
    return true
  end

  if options.token_command then
    vim.health.ok("the token comes from token_command")
    return true
  end

  if options.token_env then
    vim.health.ok(("the token comes from the environment variable %s"):format(options.token_env))
    return true
  end

  vim.health.error("no token source is configured", {
    'setup({ token_command = { "keepassxc-cli", "show", "--attributes", "Password", "<database>", "<entry>" } })',
    'or setup({ token_env = "TODOIST_API_TOKEN" })',
    'or setup({ token = "<the token>" }), which puts it in the file in clear text.',
  })

  return false
end

local function check_token(options)
  local finished, token, err = settle(function(done)
    require("todoist.token").resolve(options, done)
  end)

  if not finished then
    vim.health.error("the token source did not answer in time")
    return false
  end

  if not token then
    vim.health.error(err or "the token could not be resolved")
    return false
  end

  vim.health.ok("the token resolved")

  return true
end

local function check_request()
  local finished, _, err = settle(function(done)
    require("todoist.client").ping(done)
  end)

  if not finished then
    vim.health.error("the API did not answer in time")
    return
  end

  if err then
    vim.health.error(("the request failed: %s"):format(err.message), {
      err.kind == "unauthorized" and "The token resolved but the API refused it. It may have been revoked."
        or "Check the network and try :checkhealth todoist again.",
    })
    return
  end

  vim.health.ok("one authenticated request succeeded")
end

function M.check()
  vim.health.start("todoist.nvim")

  local options = require("todoist").options

  if not check_curl(options) then
    return
  end

  if not check_token_source(options) then
    return
  end

  if not check_token(options) then
    return
  end

  check_request()
end

return M
