-- The Todoist API v1 client.
--
-- Every request is one `curl` process spawned through `vim.system` with a
-- callback, and every result is handed back inside `vim.schedule`. Nothing here
-- waits: `request` returns while curl is still running, and the editor stays
-- interactive while a slow network takes its time. That is the whole reason the
-- client is shaped around a callback rather than a return value.
--
-- The token travels on curl's standard input as a configuration file, not in
-- its argv, so it never appears in the process table. Request bodies do go in
-- argv, because a task's content is not a secret.
--
-- Adding an endpoint means adding a three-line wrapper over `request`, the way
-- `get_task` and `update_task` are written.

local M = {}

local token_source = require("todoist.token")

--- How long to wait before the one retry of a transient failure. Todoist sends
--- `Retry-After` on a rate limit and that value wins; this is the fallback for
--- a network failure or a server error, which carry no such advice.
local RETRY_DELAY_MS = 1000

--- An upper bound on an honoured `Retry-After`. The header is advice from the
--- other end, and a request that waited minutes inside the editor would read as
--- a hang rather than as patience.
local MAX_RETRY_DELAY_MS = 10000

---@class todoist.Error
---@field kind "network"|"unauthorized"|"forbidden"|"rate_limited"|"not_found"|"http"|"malformed"|"token"
---@field message string safe to show a user: never carries the token
---@field status integer? the HTTP status, when there was one
---@field retry_after integer? seconds the API asked us to wait

---@param query table<string, string|number>?
---@return string
local function encode_query(query)
  if not query or next(query) == nil then
    return ""
  end

  local parts = {}
  for key, value in pairs(query) do
    parts[#parts + 1] = ("%s=%s"):format(key, vim.uri_encode(tostring(value), "rfc3986"))
  end

  -- Sorted, so one request always produces one URL and a test can name it.
  table.sort(parts)

  return "?" .. table.concat(parts, "&")
end

--- Split a raw `curl --include` response into its status, headers and body.
---
--- Informational blocks are skipped: a proxy or an `Expect: 100-continue` puts
--- a `1xx` block ahead of the real one, and reading the first block would report
--- the status of a response that says nothing.
---@param text string
---@return integer? status
---@return table<string, string> headers keyed in lower case
---@return string body
function M.parse_response(text)
  local rest = tostring(text or "")
  local status, headers = nil, {}

  while true do
    local head, body = rest:match("^(.-)\r?\n\r?\n(.*)$")
    if not head then
      return status, headers, rest
    end

    status = tonumber(head:match("^HTTP/[%d%.]+ (%d%d%d)"))
    headers = {}
    for name, value in head:gmatch("\n([%w%-]+):%s*([^\r\n]*)") do
      headers[name:lower()] = value
    end

    if not status or status >= 200 then
      return status, headers, body
    end

    rest = body
  end
end

--- The message the API itself gave, when it gave one.
---
--- Todoist answers an error with a JSON body carrying `error`, and its wording
--- is more use than any sentence this plugin could invent, so it is preferred
--- and the status is the fallback.
---@param body string
---@param status integer
---@return string
local function api_message(body, status)
  local ok, decoded = pcall(vim.json.decode, body)
  if ok and type(decoded) == "table" then
    local message = decoded.error or decoded.error_description
    if type(message) == "string" and message ~= "" then
      return message
    end
  end

  return ("the API answered %d"):format(status)
end

--- Turn one finished curl run into either a decoded body or a typed error.
---@param out vim.SystemCompleted
---@return any? data
---@return todoist.Error? err
function M.interpret(out)
  local status, headers, body = M.parse_response(out.stdout)

  if not status then
    -- curl exited without a response: no route, no listener, TLS refused, or
    -- the deadline passed. Its own stderr line is the most specific thing
    -- available and carries nothing secret.
    local detail = vim.trim((tostring(out.stderr or ""):match("^[^\r\n]*")) or "")
    return nil, { kind = "network", message = detail ~= "" and detail or ("curl exited " .. tostring(out.code)) }
  end

  if status == 401 then
    return nil, { kind = "unauthorized", status = status, message = "the API rejected the token" }
  elseif status == 403 then
    return nil, { kind = "forbidden", status = status, message = api_message(body, status) }
  elseif status == 429 then
    local retry_after = tonumber(headers["retry-after"])

    return nil,
      { kind = "rate_limited", status = status, retry_after = retry_after, message = "the API is rate limiting" }
  elseif status == 404 then
    return nil, { kind = "not_found", status = status, message = api_message(body, status) }
  elseif status < 200 or status >= 300 then
    return nil, { kind = "http", status = status, message = api_message(body, status) }
  end

  -- A 204 and an empty 200 both mean the call worked and said nothing.
  if vim.trim(body) == "" then
    return true
  end

  local ok, decoded = pcall(vim.json.decode, body)
  if not ok then
    return nil, { kind = "malformed", status = status, message = "the API answered with something that is not JSON" }
  end

  return decoded
end

--- Whether a failure is worth one more attempt. A refused token is not: the
--- API's own guidance is that retrying an invalid token only spends the rate
--- limit, and the answer would not change in a second.
---@param err todoist.Error
---@return boolean
function M.is_transient(err)
  return err.kind == "network" or err.kind == "rate_limited" or (err.kind == "http" and (err.status or 0) >= 500)
end

--- How long to wait before that attempt. `Retry-After` wins when the API sent
--- one, bounded at both ends.
---@param err todoist.Error
---@return integer milliseconds
function M.retry_delay(err)
  local advised = (err.retry_after or 0) * 1000

  return math.min(math.max(advised, RETRY_DELAY_MS), MAX_RETRY_DELAY_MS)
end

---@param err todoist.Error
---@param retried boolean? whether a retry was actually spent on this failure
local function notify(err, retried)
  local message = "todoist.nvim: " .. err.message

  if err.kind == "unauthorized" then
    message = message .. ". Check the token_command or token_env named in setup"
  elseif retried then
    message = message .. " (retried once)"
  end

  vim.notify(message, vim.log.levels.WARN)
end

---@class todoist.Request
---@field method "GET"|"POST"|"DELETE"
---@field path string appended to `base_url`, for example "/tasks/6XGg"
---@field query table<string, string|number>? URL parameters
---@field body table? encoded as the JSON request body
---@field quiet boolean? suppress the notification and report the error only

---@param options todoist.Options
---@param spec todoist.Request
---@param token string
---@param callback fun(out: vim.SystemCompleted)
---@return boolean spawned
---@return string? reason
local function spawn(options, spec, token, callback)
  local argv = {
    vim.fs.normalize(options.curl),
    "--silent",
    "--show-error",
    "--include",
    "--max-time",
    tostring(options.timeout),
    -- Reads the Authorization header off stdin, keeping it out of the argv.
    "--config",
    "-",
    "--request",
    spec.method,
    options.base_url .. spec.path .. encode_query(spec.query),
  }

  if spec.body then
    vim.list_extend(argv, { "--header", "Content-Type: application/json", "--data-binary", vim.json.encode(spec.body) })
  end

  local config = ('header = "Authorization: Bearer %s"\nheader = "Accept: application/json"\n'):format(token)

  -- `vim.system` raises on a curl that is not there, so the spawn is wrapped
  -- rather than preceded by an executable check.
  return pcall(vim.system, argv, { text = true, stdin = config }, callback)
end

--- Make one authenticated request.
---
--- Returns immediately, before the request is made. `callback(data, err)` runs
--- later on the main loop with exactly one of the two set. A transient failure
--- (no network, a server error, a rate limit) is retried once, honouring
--- `Retry-After`; a rejected token is not retried, because retrying an invalid
--- token only spends the rate limit. Every failure raises one `vim.notify` at
--- WARN unless the request asked to be quiet, and no message anywhere contains
--- the token.
---@param spec todoist.Request
---@param callback fun(data: any?, err: todoist.Error?)
function M.request(spec, callback)
  local options = require("todoist").options

  local function fail(err, retried)
    vim.schedule(function()
      if not spec.quiet then
        notify(err, retried)
      end
      callback(nil, err)
    end)
  end

  local attempt
  attempt = function(token, retries_left, is_retry)
    local spawned = spawn(options, spec, token, function(out)
      local data, err = M.interpret(out)

      vim.schedule(function()
        if not err then
          return callback(data)
        end

        if err.kind == "unauthorized" then
          -- The cached token is the one that was refused, so the next request
          -- asks its source again rather than repeating a known bad value.
          token_source.forget()
        end

        if retries_left > 0 and M.is_transient(err) then
          return vim.defer_fn(function()
            attempt(token, retries_left - 1, true)
          end, M.retry_delay(err))
        end

        fail(err, is_retry)
      end)
    end)

    if not spawned then
      -- The pcall error carries an internal Neovim source location, which
      -- means nothing to a user; only the executable and a hint do.
      fail({ kind = "network", message = ("%s could not be run. Check the curl option"):format(options.curl) })
    end
  end

  token_source.resolve(options, function(token, err)
    if not token then
      return fail({ kind = "token", message = err or "the token could not be resolved" })
    end

    attempt(token, 1)
  end)
end

--- The one cheap authenticated call, used by the health check to prove that the
--- token works without asking for anything in particular.
---@param callback fun(data: any?, err: todoist.Error?)
function M.ping(callback)
  M.request({ method = "GET", path = "/projects", query = { limit = 1 }, quiet = true }, callback)
end

--- One task, whole.
---@param id string
---@param callback fun(task: table?, err: todoist.Error?)
function M.get_task(id, callback)
  M.request({ method = "GET", path = "/tasks/" .. id }, callback)
end

--- Write fields back to one task.
---
--- Todoist takes a partial object, so only what is passed changes. The fields a
--- task buffer edits are `content`, `description`, `due_string`, `priority` and
--- `labels`.
---@param id string
---@param fields table
---@param callback fun(task: table?, err: todoist.Error?)
function M.update_task(id, fields, callback)
  M.request({ method = "POST", path = "/tasks/" .. id, body = fields }, callback)
end

return M
