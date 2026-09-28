local M = {}

local format = require("damnit.list_format")
local message = require("damnit.message")

local BRACKETED_PASTE_START = "\27[200~"
local BRACKETED_PASTE_END = "\27[201~"

local SHORT_OID_LENGTH = 7

local DEFAULT_LEAST_URGENT_PRIORITY = 4

local NO_RECORD = "no hand-off record written"

local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

function M.brief(object, note)
  local window = require("damnit.window")
  local lines = {
    "dam task: " .. vim.trim(text(object.subject)),
    "oid: " .. text(object.oid):sub(1, SHORT_OID_LENGTH),
    "store: " .. window.store_display(require("damnit.queue").key()),
  }

  local path = text(object.path)
  if path ~= "" then
    lines[#lines + 1] = "path: " .. path
  end

  local due = format.due_of(object)
  if due ~= "" then
    lines[#lines + 1] = "due: " .. due
  end

  local priority = tonumber(type(object.task) == "table" and object.task.priority or nil)
  if priority and priority < DEFAULT_LEAST_URGENT_PRIORITY then
    lines[#lines + 1] = ("priority: p%d"):format(priority)
  end

  local labels = format.labels_of(object)
  if #labels > 0 then
    lines[#lines + 1] = "labels: " .. table.concat(labels, ", ")
  end

  local body = vim.trim(text(object.body))
  if body ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = body
  end

  local written = vim.trim(text(note))
  if written ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "note: " .. written
  end

  return table.concat(lines, "\n")
end

local function without_paste_terminators(brief)
  local body, removed = brief, 1

  while removed > 0 do
    body, removed = body:gsub(vim.pesc(BRACKETED_PASTE_END), "")
  end

  return body
end

function M.pasted(brief)
  return BRACKETED_PASTE_START .. without_paste_terminators(brief) .. BRACKETED_PASTE_END
end

local AGENT_NAME_FIELDS_RUNNING_BEFORE_SIGNED_IN = { "agent", "display_agent" }

local function named(listed)
  for _, field in ipairs(AGENT_NAME_FIELDS_RUNNING_BEFORE_SIGNED_IN) do
    if text(listed[field]) ~= "" then
      return text(listed[field])
    end
  end

  return "the agent"
end

function M.agent_in(listing, workspace, me)
  local ok, answer = pcall(vim.json.decode, listing)
  if not ok or type(answer) ~= "table" then
    return nil, "herdr agent list answered with something unreadable"
  end

  for _, listed in ipairs(vim.tbl_get(answer, "result", "agents") or {}) do
    local names_an_agent = text(listed.agent) ~= ""
    local is_this_pane = text(listed.pane_id) == text(me)
    local in_another_workspace = text(listed.workspace_id) ~= text(workspace)
    if names_an_agent and not is_this_pane and not in_another_workspace then
      return { pane = text(listed.pane_id), name = named(listed) }
    end
  end

  return nil, "no agent pane in this workspace"
end

local function copy(host, brief, because)
  local reached_system_clipboard = host.copy(brief)
  local reason = because and (because .. "; ") or ""
  local where = reached_system_clipboard and "the clipboard" or "the unnamed register, no clipboard provider"
  local said = ("%scopied the brief to %s, %s"):format(reason, where, NO_RECORD)

  if because then
    return message.warn(said)
  end

  message.say(said)
end

local function focus_as_a_convenience(host, pane)
  host.run({ "agent", "focus", pane }, function() end)
end

function M.hand_off(object, note, host)
  local brief = M.brief(object, note)

  if not host.in_herdr then
    return copy(host, brief)
  end

  host.run({ "agent", "list" }, function(listing, err)
    if err then
      return copy(host, brief, err)
    end

    local agent, why = M.agent_in(listing, host.workspace, host.me)
    if not agent then
      return copy(host, brief, why)
    end

    host.run({ "pane", "send-text", agent.pane, M.pasted(brief) }, function(_, refusal)
      if refusal then
        return copy(host, brief, ("herdr refused the send to %s"):format(agent.pane))
      end

      focus_as_a_convenience(host, agent.pane)

      message.say(("sent to %s, %s"):format(agent.name, NO_RECORD))
    end)
  end)
end

function M.host()
  return {
    in_herdr = text(vim.env.HERDR_ENV) ~= "",
    workspace = vim.env.HERDR_WORKSPACE_ID,
    me = vim.env.HERDR_PANE_ID,
    run = function(args, done)
      local dam = require("damnit.dam")
      local binary = vim.env.HERDR_BIN_PATH
      if text(binary) == "" then
        binary = "herdr"
      end

      local command = vim.list_extend({ binary }, args)

      dam.spawn(command, dam.timeout_seconds(), function(out)
        if out.missing then
          return done("", ("%s: no such file or directory"):format(binary))
        end

        local failure = out.code ~= 0 and vim.trim(("%s: %s"):format(binary, out.stderr or "")) or nil

        done(out.stdout or "", failure)
      end)
    end,
    copy = function(brief)
      vim.fn.setreg('"', brief)
      if vim.fn.has("clipboard") ~= 1 then
        return false
      end

      vim.fn.setreg("+", brief)
      return true
    end,
  }
end

function M.send()
  local object = require("damnit.list").object_under_cursor()
  if not object then
    return
  end

  vim.ui.input({ prompt = "Note: " }, function(note)
    local escaped = note == nil
    if escaped then
      return
    end

    M.hand_off(object, note, M.host())
  end)
end

return M
