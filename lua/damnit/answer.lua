local M = {}

M.MISSING = "dam was not found on PATH; install it with cargo install damnit"

local DEFAULT_TIMEOUT_SECONDS = 120

local TIMEOUT_EXIT_CODE = 124

local KIND_BY_EXIT_CODE = { [1] = "error", [2] = "usage", [3] = "cancelled", [4] = "refused" }

function M.message_of(stderr)
  local text = vim.trim(tostring(stderr or ""))

  return (text:gsub("^dam: ", ""))
end

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

local function silent_failure(label, code, named)
  local call = label or "a dam call"

  if named then
    return ("%s failed with exit %d: dam said %s and nothing more"):format(call, code, named)
  end

  return ("%s failed with exit %d and said nothing"):format(call, code)
end

local function killed_by_a_signal(out)
  return out.code == 0 and (out.signal or 0) ~= 0
end

function M.interpret(out, label, seconds)
  if out.missing then
    return nil, { kind = "missing", code = -1, plugin = true, message = M.MISSING }
  end

  if killed_by_a_signal(out) then
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

  if out.code == TIMEOUT_EXIT_CODE then
    return nil,
      {
        kind = "timeout",
        code = TIMEOUT_EXIT_CODE,
        plugin = true,
        message = ("%s took longer than %ds and was stopped"):format(
          label or "a dam call",
          tonumber(seconds) or DEFAULT_TIMEOUT_SECONDS
        ),
      }
  end

  local document = document_of(out.stderr)
  local kind = KIND_BY_EXIT_CODE[out.code] or "error"
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
