local M = {}

local dam_object = require("damnit.object")
local text = dam_object.text
local format = require("damnit.list_format")
local list = require("damnit.list")
local store = require("damnit.store")
local timeout_seconds = require("damnit.process").timeout_seconds

local BRACKETED_PASTE_START = "\27[200~"
local BRACKETED_PASTE_END = "\27[201~"

local DEFAULT_LEAST_URGENT_PRIORITY = 4

local NO_RECORD = "no hand-off record written"

function M.brief(app, object, note)
  local lines = {
    "dam task: " .. vim.trim(text(object.subject)),
    "oid: " .. dam_object.short_oid(object.oid),
    "store: " .. store.display(app.store),
  }

  local path = text(object.path)
  if path ~= "" then
    lines[#lines + 1] = "path: " .. path
  end

  local due = format.due_of(object)
  if due ~= "" then
    lines[#lines + 1] = "due: " .. due
  end

  local priority = tonumber(dam_object.task(object).priority)
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

local function copy(app, host, brief, because)
  local reached_system_clipboard = host.copy(brief)
  local reason = because and (because .. "; ") or ""
  local where = reached_system_clipboard and "the clipboard" or "the unnamed register, no clipboard provider"
  local said = ("%scopied the brief to %s, %s"):format(reason, where, NO_RECORD)

  if because then
    return app.say.warn(said)
  end

  app.say.info(said)
end

local function focus_as_a_convenience(host, pane)
  host.run({ "agent", "focus", pane }, function() end)
end

function M.hand_off(app, object, note, host)
  local brief = M.brief(app, object, note)

  if not host.in_herdr then
    return copy(app, host, brief)
  end

  host.run({ "agent", "list" }, function(listing, err)
    if err then
      return copy(app, host, brief, err)
    end

    local agent, why = M.agent_in(listing, host.workspace, host.me)
    if not agent then
      return copy(app, host, brief, why)
    end

    host.run({ "pane", "send-text", agent.pane, M.pasted(brief) }, function(_, refusal)
      if refusal then
        return copy(app, host, brief, ("herdr refused the send to %s"):format(agent.pane))
      end

      focus_as_a_convenience(host, agent.pane)

      app.say.info(("sent to %s, %s"):format(agent.name, NO_RECORD))
    end)
  end)
end

function M.host(app)
  return {
    in_herdr = text(vim.env.HERDR_ENV) ~= "",
    workspace = vim.env.HERDR_WORKSPACE_ID,
    me = vim.env.HERDR_PANE_ID,
    run = function(args, done)
      local binary = vim.env.HERDR_BIN_PATH
      if text(binary) == "" then
        binary = "herdr"
      end

      local command = vim.list_extend({ binary }, args)

      app.process.run(command, timeout_seconds(app.options), function(out)
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

function M.send(app)
  local object = list.object_under_cursor(app)
  if not object then
    return
  end

  vim.ui.input({ prompt = "Note: " }, function(note)
    local escaped = note == nil
    if escaped then
      return
    end

    M.hand_off(app, object, note, M.host(app))
  end)
end

return M
