-- One finished dam process into a result or an error.
--
-- Under --json dam answers on standard output and, on a failure, writes one
-- error document on standard error. This module is pure over a
-- `vim.SystemCompleted`: it spawns nothing, schedules nothing and says nothing.

local M = {}

M.MISSING = "dam was not found on PATH; install it with cargo install damnit"

--- The seconds a timeout names when the caller did not say. It is the default
--- of the option the caller reads.
local DEFAULT_TIMEOUT = 120

--- Exit code to error kind, for a failure that carried no document. 0 is
--- success and is handled before this table. dam's own kind is used instead
--- wherever it wrote one.
local KINDS = { [1] = "error", [2] = "usage", [3] = "cancelled", [4] = "refused" }

---@class damnit.Error
---@field kind "refused"|"store"|"helper"|"credential"|"parse"|"usage"|"cancelled"|"error"|"timeout"|"missing"|"unsupported"|"malformed"
---@field code integer the exit code, or -1 when nothing ran
---@field message string ready to show: dam's own sentence, or this plugin's
---@field rule string? the rule a refusal broke, as dam names it
---@field oids string[]? the objects dam's message names, in the order it names them
---@field plugin boolean? true when this plugin composed the message

--- Standard error that is not a document: clap's own usage text, or the plain
--- line a human format writes.
---@param stderr string?
---@return string
function M.message_of(stderr)
  local text = vim.trim(tostring(stderr or ""))

  return (text:gsub("^dam: ", ""))
end

--- The error document dam writes on standard error under --json, or nil when
--- standard error holds something else.
---@param stderr string?
---@return table?
local function document_of(stderr)
  local text = vim.trim(tostring(stderr or ""))
  if text == "" then
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, text, { luanil = { object = true } })
  if not ok or type(decoded) ~= "table" or type(decoded.error) ~= "table" then
    return nil
  end

  return decoded.error
end

--- The document's oid list, or nil when it is not a list of oids.
---@param value any
---@return string[]?
local function oids_of(value)
  if not vim.islist(value) then
    return nil
  end

  for _, oid in ipairs(value) do
    if type(oid) ~= "string" then
      return nil
    end
  end

  return value
end

--- What to say about a failure that carried no sentence of its own.
---@param label string?
---@param code integer
---@param named string? dam's rule, or its kind, where it sent a document
---@return string
local function silent_failure(label, code, named)
  local call = label or "a dam call"

  if named then
    return ("%s failed with exit %d: dam said %s and nothing more"):format(call, code, named)
  end

  return ("%s failed with exit %d and said nothing"):format(call, code)
end

--- One finished process into a result or an error.
---@param out table a vim.SystemCompleted, or one this module synthesised
---@param label string? what to call the call in a timeout message
---@param seconds integer? how long the call was allowed to run
---@return table? data
---@return damnit.Error? err
function M.interpret(out, label, seconds)
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
    return nil,
      {
        kind = "timeout",
        code = 124,
        plugin = true,
        message = ("%s took longer than %ds and was stopped"):format(
          label or "a dam call",
          tonumber(seconds) or DEFAULT_TIMEOUT
        ),
      }
  end

  local document = document_of(out.stderr)
  local kind = KINDS[out.code] or "error"
  local rule, oids, named

  if document then
    kind = type(document.kind) == "string" and document.kind or kind
    rule = type(document.rule) == "string" and document.rule or nil
    oids = oids_of(document.oids)
    named = rule or kind
  end

  local text = document and tostring(document.message or "") or M.message_of(out.stderr)
  if text == "" then
    return nil,
      {
        kind = kind,
        code = out.code,
        rule = rule,
        oids = oids,
        plugin = true,
        message = silent_failure(label, out.code, named),
      }
  end

  return nil, { kind = kind, code = out.code, rule = rule, oids = oids, message = text }
end

return M
