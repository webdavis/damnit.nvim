-- The one module that spawns a process.
--
-- Every call is argv, never a shell string, so a subject holding a quote or a
-- newline is an argument and nothing else. Every call carries `--json`. Every
-- result is marshalled through `vim.schedule` before it reaches the caller,
-- because a `vim.system` callback runs on the libuv loop where most of the API
-- is not allowed.

local M = {}

local message = require("damnit.message")

--- The dam versions this plugin speaks to, low inclusive and high exclusive.
M.MIN_VERSION = "0.1.0"
M.MAX_VERSION = "0.2.0"

M.MISSING = "dam was not found on PATH; install it with cargo install damnit"

--- Exit code to error kind. 0 is success and is handled before this table.
local KINDS = { [1] = "error", [2] = "refused", [3] = "cancelled" }

--- The version this session read, or nil when the banner was unreadable.
---@type string?
M.version = nil

---@type "unknown"|"ok"|"refused"
local state = "unknown"

---@type damnit.Error?
local refusal = nil

---@type fun(err: damnit.Error?)[]
local waiting = {}

--- Bumped by every `forget`. A handshake answers for the session it began in.
local generation = 0

---@class damnit.Error
---@field kind "error"|"refused"|"cancelled"|"timeout"|"missing"|"unsupported"|"malformed"
---@field code integer the exit code, or -1 when nothing ran
---@field message string ready to show: dam's own line, or this plugin's sentence
---@field plugin boolean? true when this plugin composed the message

--- The full argv for a call, `dam` and the global flags included.
---@param args string[] the subcommand and its flags, `--json` included
---@return string[]
function M.argv(args)
  local options = require("damnit").options
  local argv = { "dam" }

  for _, flag in ipairs({ "store", "config" }) do
    local value = options[flag]
    if type(value) == "string" and value ~= "" then
      vim.list_extend(argv, { "--" .. flag, value })
    end
  end

  vim.list_extend(argv, args)

  return argv
end

--- dam writes its errors as one plain line prefixed `dam: `, even under --json,
--- and a refusal's detail follows on further lines.
---@param stderr string?
---@return string
function M.message_of(stderr)
  local text = vim.trim(tostring(stderr or ""))

  return (text:gsub("^dam: ", ""))
end

---@param text string
---@return integer[]? parts
local function parts_of(text)
  local major, minor, patch = tostring(text):match("^(%d+)%.(%d+)%.(%d+)$")
  if not major then
    return nil
  end

  return { tonumber(major), tonumber(minor), tonumber(patch) }
end

---@param left integer[]
---@param right integer[]
---@return integer -1, 0 or 1
local function compare(left, right)
  for index = 1, 3 do
    if left[index] ~= right[index] then
      return left[index] < right[index] and -1 or 1
    end
  end

  return 0
end

--- Whether a version string is one this plugin speaks to.
---@param text string
---@return boolean
function M.supported(text)
  local parts = parts_of(text)
  if not parts then
    return false
  end

  return compare(parts, parts_of(M.MIN_VERSION)) >= 0 and compare(parts, parts_of(M.MAX_VERSION)) < 0
end

--- One finished process into a result or an error.
---@param out table a vim.SystemCompleted, or one this module synthesised
---@param label string? what to call the call in a timeout message
---@return table? data
---@return damnit.Error? err
function M.interpret(out, label)
  if out.missing then
    return nil, { kind = "missing", code = -1, plugin = true, message = M.MISSING }
  end

  -- A process a signal killed reports code 0, so an unguarded code 0 reads a
  -- cancelled call as an empty answer.
  if out.code == 0 and (out.signal or 0) ~= 0 then
    local text = M.message_of(out.stderr)
    if text == "" then
      return nil,
        { kind = "cancelled", code = 3, plugin = true, message = ("%s was stopped"):format(label or "a dam call") }
    end

    return nil, { kind = "cancelled", code = 3, message = text }
  end

  if out.code == 0 then
    local ok, decoded = pcall(vim.json.decode, out.stdout or "", { luanil = { object = true } })
    if not ok or type(decoded) ~= "table" then
      return nil,
        { kind = "malformed", code = 0, plugin = true, message = "dam answered with something that is not JSON" }
    end

    return decoded, nil
  end

  if out.code == 124 then
    local seconds = tonumber(require("damnit").options.timeout) or 120

    return nil,
      {
        kind = "timeout",
        code = 124,
        plugin = true,
        message = ("%s took longer than %ds and was stopped"):format(label or "a dam call", seconds),
      }
  end

  return nil, { kind = KINDS[out.code] or "error", code = out.code, message = M.message_of(out.stderr) }
end

--- Spawn one `dam`, answering on the main loop.
---
--- `vim.system` throws when the binary is absent rather than calling back, so
--- the spawn is wrapped and the absence arrives as an ordinary answer.
---@param args string[]
---@param on_exit fun(out: table)
---@return table? handle
local function spawn(args, on_exit)
  local seconds = math.max(tonumber(require("damnit").options.timeout) or 120, 1)

  local ok, handle = pcall(vim.system, M.argv(args), { text = true, timeout = seconds * 1000 }, function(out)
    vim.schedule(function()
      on_exit(out)
    end)
  end)

  if not ok then
    vim.schedule(function()
      on_exit({ code = -1, stdout = "", stderr = "", missing = true })
    end)

    return nil
  end

  return handle
end

--- Answer every caller waiting on the handshake, then clear the list.
---@param err damnit.Error?
local function settle_handshake(err)
  local callbacks = waiting
  waiting = {}

  for _, callback in ipairs(callbacks) do
    callback(err)
  end
end

--- Read `dam --version` once per session and decide whether to speak to it.
---@param callback fun(err: damnit.Error?)
local function handshake(callback)
  if state == "ok" then
    return callback(nil)
  end

  if state == "refused" then
    return callback(refusal)
  end

  table.insert(waiting, callback)
  if #waiting > 1 then
    return
  end

  local session = generation

  spawn({ "--version" }, function(out)
    -- A probe begun under the options of an earlier session says nothing about
    -- the dam the current options name.
    if session ~= generation then
      return
    end

    local banner = vim.trim(tostring(out.stdout or ""))
    local version = banner:match("dam%s+(%d+%.%d+%.%d+)")

    if out.missing or (out.code ~= 0 and not version) then
      state = "refused"
      refusal = { kind = "missing", code = -1, plugin = true, message = M.MISSING }
    elseif not version then
      -- An unreadable banner is not a reason to refuse to work. A wrong JSON
      -- shape fails loudly at the call that needs it.
      state = "ok"
      M.version = nil
      message.warn(("dam --version printed %q, which is not a version; going on anyway"):format(banner))
    elseif not M.supported(version) then
      state = "refused"
      refusal = {
        kind = "unsupported",
        code = 0,
        plugin = true,
        message = ("dam %s is outside the supported range >=%s <%s; update damnit.nvim"):format(
          version,
          M.MIN_VERSION,
          M.MAX_VERSION
        ),
      }
    else
      state = "ok"
      M.version = version
    end

    settle_handshake(state == "ok" and nil or refusal)
  end)
end

--- Forget the handshake, so the next call runs it again. `setup` calls this,
--- because new options may name a different dam.
function M.forget()
  generation = generation + 1
  state = "unknown"
  refusal = nil
  waiting = {}
  M.version = nil
end

--- Make one `dam` call. The one entry point every other module uses.
---@param args string[] the subcommand and its flags, `--json` included
---@param opts { label: string?, on_spawn: fun(handle: table?) }?
---@param callback fun(data: table?, err: damnit.Error?)
function M.call(args, opts, callback)
  opts = opts or {}

  handshake(function(err)
    if err then
      return callback(nil, err)
    end

    local handle = spawn(args, function(out)
      callback(M.interpret(out, opts.label))
    end)

    if opts.on_spawn then
      opts.on_spawn(handle)
    end
  end)
end

return M
