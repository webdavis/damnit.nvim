local M = {}

local answer = require("damnit.answer")
local message = require("damnit.message")
local process = require("damnit.process")
local verbs = require("damnit.dam.verbs")

M.MIN_VERSION = "0.2.0"
M.MAX_VERSION = "0.3.0"

M.version = nil

local handshake_state = "unknown"

local handshake_refusal = nil

local waiting_on_handshake = {}

local options_generation = 0

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

local function parts_of(text)
  local major, minor, patch = tostring(text):match("^(%d+)%.(%d+)%.(%d+)$")
  if not major then
    return nil
  end

  return { tonumber(major), tonumber(minor), tonumber(patch) }
end

local function compare(left, right)
  for index = 1, 3 do
    if left[index] ~= right[index] then
      return left[index] < right[index] and -1 or 1
    end
  end

  return 0
end

function M.supported(text)
  local parts = parts_of(text)
  if not parts then
    return false
  end

  return compare(parts, parts_of(M.MIN_VERSION)) >= 0 and compare(parts, parts_of(M.MAX_VERSION)) < 0
end

local function timeout_seconds()
  return process.timeout_seconds(require("damnit").options)
end

local function spawn(args, seconds, on_exit)
  return process.run(M.argv(args), seconds, on_exit)
end

local function settle_handshake(err)
  local callbacks = waiting_on_handshake
  waiting_on_handshake = {}

  for _, callback in ipairs(callbacks) do
    callback(err)
  end
end

local function handshake(callback)
  if handshake_state == "ok" then
    return callback(nil)
  end

  if handshake_state == "refused" then
    return callback(handshake_refusal)
  end

  table.insert(waiting_on_handshake, callback)
  if #waiting_on_handshake > 1 then
    return
  end

  local generation_at_start = options_generation

  spawn(verbs.version(), timeout_seconds(), function(out)
    local began_under_old_options = generation_at_start ~= options_generation
    if began_under_old_options then
      return
    end

    local banner = vim.trim(tostring(out.stdout or ""))
    local version = banner:match("dam%s+(%d+%.%d+%.%d+)")

    if out.missing or (out.code ~= 0 and not version) then
      handshake_state = "refused"
      handshake_refusal = { kind = "missing", code = -1, plugin = true, message = answer.MISSING }
    elseif not version then
      handshake_state = "ok"
      M.version = nil
      message.warn(("dam --version printed %q, which is not a version; going on anyway"):format(banner))
    elseif not M.supported(version) then
      handshake_state = "refused"
      handshake_refusal = {
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
      handshake_state = "ok"
      M.version = version
    end

    settle_handshake(handshake_state == "ok" and nil or handshake_refusal)
  end)
end

local function release_callers_of_the_old_handshake()
  settle_handshake({
    kind = "cancelled",
    code = -1,
    plugin = true,
    message = "the dam call was dropped when the options changed",
  })
end

function M.forget()
  options_generation = options_generation + 1
  handshake_state = "unknown"
  handshake_refusal = nil
  M.version = nil

  release_callers_of_the_old_handshake()
end

function M.call(args, opts, callback)
  opts = opts or {}

  handshake(function(err)
    if err then
      return callback(nil, err)
    end

    local seconds = timeout_seconds()

    local handle = spawn(args, seconds, function(out)
      callback(answer.interpret(out, opts.label, seconds))
    end)

    if opts.on_spawn then
      opts.on_spawn(handle)
    end
  end)
end

return M
