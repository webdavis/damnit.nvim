-- The one module that spawns a process.
--
-- Every call is argv, never a shell string, so a subject holding a quote or a
-- newline is an argument and nothing else. Every call carries `--json`. Every
-- result is marshalled through `vim.schedule` before it reaches the caller,
-- because a `vim.system` callback runs on the libuv loop where most of the API
-- is not allowed.

local M = {}

local answer = require("damnit.answer")
local message = require("damnit.message")

--- The dam versions this plugin speaks to, low inclusive and high exclusive.
--- 0.2.0 is the release that answers a failure with an error document.
M.MIN_VERSION = "0.2.0"
M.MAX_VERSION = "0.3.0"

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

--- How long one call may run before `vim.system` stops it.
---@return integer seconds
function M.timeout_seconds()
  return math.max(tonumber(require("damnit").options.timeout) or 120, 1)
end

--- Spawn one process, answering on the main loop.
---
--- `vim.system` throws when the binary is absent rather than calling back, so
--- the spawn is wrapped and the absence arrives as an ordinary answer with
--- `missing` set.
---
--- This is the plugin's one spawn. `dam` is what it is for, and the agent
--- hand-off reaches `herdr` through it rather than opening a second one.
---@param argv string[] the whole command line, the binary included
---@param seconds integer how long the call may run
---@param on_exit fun(out: table)
---@return table? handle
function M.spawn(argv, seconds, on_exit)
  local ok, handle = pcall(vim.system, argv, { text = true, timeout = seconds * 1000 }, function(out)
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

--- Spawn one `dam`, with the global flags the options name in front of `args`.
---@param args string[]
---@param seconds integer how long the call may run
---@param on_exit fun(out: table)
---@return table? handle
local function spawn(args, seconds, on_exit)
  return M.spawn(M.argv(args), seconds, on_exit)
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

  spawn({ "--version" }, M.timeout_seconds(), function(out)
    -- A probe begun under the options of an earlier session says nothing about
    -- the dam the current options name.
    if session ~= generation then
      return
    end

    local banner = vim.trim(tostring(out.stdout or ""))
    local version = banner:match("dam%s+(%d+%.%d+%.%d+)")

    if out.missing or (out.code ~= 0 and not version) then
      state = "refused"
      refusal = { kind = "missing", code = -1, plugin = true, message = answer.MISSING }
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
  M.version = nil

  -- A caller waiting on the old handshake is answered rather than dropped: an
  -- unanswered call leaves its queue lane running for the rest of the session.
  settle_handshake({
    kind = "cancelled",
    code = -1,
    plugin = true,
    message = "the dam call was dropped when the options changed",
  })
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

    local seconds = M.timeout_seconds()

    local handle = spawn(args, seconds, function(out)
      callback(answer.interpret(out, opts.label, seconds))
    end)

    if opts.on_spawn then
      opts.on_spawn(handle)
    end
  end)
end

return M
