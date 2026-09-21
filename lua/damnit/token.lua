-- The token boundary.
--
-- A Todoist token is a password: it opens the whole account. So it enters this
-- plugin by exactly three doors, every one of them named by the user, and
-- leaves by none. It is never read from a well-known path, and never part of a
-- message, a log line or a health report. Failures here name the SOURCE that
-- failed and say nothing about what it produced, which is why a failed
-- command's own output is dropped rather than quoted: a program that prints a
-- secret on the wrong stream must not have it copied into a notification.

local M = {}

--- A user-supplied command may be a vault call that unlocks something, so this
--- waits longer than a request does.
local COMMAND_TIMEOUT_MS = 10000

--- The token for this session, once a source produced one. Cached because the
--- source is typically a vault command, and asking it again per request would
--- turn every keystroke that writes a task into a second process.
local cached = nil

--- Forget a resolved token, so the next request resolves it again. Called when
--- options change and when the API rejects the token.
function M.forget()
  cached = nil
end

--- The first line, stripped of surrounding whitespace. A vault command ends its
--- output with a newline, and a token never contains one.
---@param text string?
---@return string
local function first_line(text)
  return vim.trim((tostring(text or ""):match("^[^\r\n]*")) or "")
end

--- Whether a token can be carried in a curl configuration file unchanged.
---
--- The token reaches curl through its stdin rather than its argv, so it stays
--- out of the process table, and that transport is a quoted string. A value
--- carrying a quote, a backslash or a newline would either break the quoting or
--- smuggle a second option in, so it is refused instead of escaped.
---@param token string
---@return boolean
local function is_carriable(token)
  return token ~= "" and not token:find('[%c"\\]')
end

---@param token string
---@param callback fun(token: string?, err: string?)
local function accept(token, callback)
  if not is_carriable(token) then
    -- No sample of the value, not even its length.
    return callback(nil, "the token source produced something that is not a token")
  end

  cached = token
  callback(token)
end

---@param command string[]
---@param callback fun(token: string?, err: string?)
local function from_command(command, callback)
  local name = command[1] or "token_command"

  local spawned, err = pcall(vim.system, command, { text = true, timeout = COMMAND_TIMEOUT_MS }, function(out)
    vim.schedule(function()
      if out.code ~= 0 then
        return callback(nil, ("token_command %s exited %d"):format(name, out.code))
      end

      accept(first_line(out.stdout), callback)
    end)
  end)

  if not spawned then
    callback(nil, ("token_command %s could not be run: %s"):format(name, first_line(err)))
  end
end

--- Resolve the token from whichever source the options name.
---
--- The command path answers on a later tick and the environment path answers
--- immediately. Either way no caller of this is allowed to block on it, and the
--- client treats both the same.
---@param options damnit.Options
---@param callback fun(token: string?, err: string?)
function M.resolve(options, callback)
  if cached then
    return callback(cached)
  end

  if options.token then
    if type(options.token) ~= "string" then
      return callback(nil, "token must be the token as a string")
    end

    return accept(first_line(options.token), callback)
  end

  if options.token_command then
    if type(options.token_command) ~= "table" or not options.token_command[1] then
      return callback(nil, 'token_command must be a command as a list, for example { "pass", "todoist" }')
    end

    return from_command(options.token_command, callback)
  end

  if options.token_env then
    local value = vim.env[options.token_env]
    if value == nil or value == "" then
      return callback(nil, ("the environment variable %s named by token_env is not set"):format(options.token_env))
    end

    return accept(first_line(value), callback)
  end

  callback(
    nil,
    "no token source: set token_command to a command that prints the token, token_env to the name of a variable holding it, or token to the token itself"
  )
end

return M
