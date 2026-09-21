-- `S`: hand the object under the cursor to the agent, the way the herdr pane
-- does.
--
-- The brief is plain text because an agent pane is a shell, not a structure. In
-- herdr it goes into the agent pane's input as one bracketed paste and is never
-- submitted, so the operator reads it, adds to it and presses return
-- themselves. Outside herdr, and whenever herdr cannot take it, the same brief
-- goes to the clipboard and the notification says so.
--
-- dam has no comments, so a hand-off leaves no record in the store. Every
-- notification ends by saying that, on the path that delivered as well as on
-- the ones that fell back.

local M = {}

local format = require("damnit.list_format")
local message = require("damnit.message")

--- The frame `herdr pane send-text` writes the brief inside. A paste is
--- inserted verbatim by any input, where the raw bytes of a multi-line brief
--- would each be read as a key and a newline would submit it.
local PASTE_START = "\27[200~"
local PASTE_END = "\27[201~"

--- The short form of an oid, which is what an agent would type at `dam show`.
local SHORT = 7

--- dam's least urgent priority, and its default, which is left off the brief.
local LEAST_URGENT = 4

--- What every hand-off ends with, because dam has no comments to write one on.
local NO_RECORD = "no hand-off record written"

---@param value any
---@return string
local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

--- The object as the agent reads it: what it is, the oid to look it up by, the
--- store it is in, then whichever of the path, the due date, the priority and
--- the labels it has, then its body, then the note.
---
--- A field the object has nothing for is left out rather than written empty, so
--- the brief carries no line an agent has to discount. There is no URL: a dam
--- object is local.
---@param object table
---@param note string?
---@return string
function M.brief(object, note)
  local window = require("damnit.window")
  local lines = {
    "dam task: " .. vim.trim(text(object.subject)),
    "oid: " .. text(object.oid):sub(1, SHORT),
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

  -- dam's scale runs 1 to 4 with 1 the most urgent. Its default says nothing,
  -- so it goes out only when somebody set it.
  local priority = tonumber(type(object.task) == "table" and object.task.priority or nil)
  if priority and priority < LEAST_URGENT then
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

--- The brief as one bracketed paste. A terminator inside the brief would end
--- the frame early, so every one is taken out, and taking one out cannot splice
--- another together because the removal repeats until none is left.
---@param brief string
---@return string
function M.pasted(brief)
  local body, removed = brief, 1

  while removed > 0 do
    body, removed = body:gsub(vim.pesc(PASTE_END), "")
  end

  return PASTE_START .. body .. PASTE_END
end

--- What the hand-off calls the agent. `agent` is what is running in the pane;
--- `display_agent` is the auth profile it signed in with, which two panes
--- running different agents can share, so it is asked only once `agent` has
--- nothing.
---@param listed table
---@return string
local function named(listed)
  -- Read one at a time: a table literal of these two stops at the first
  -- absent one.
  for _, field in ipairs({ "agent", "display_agent" }) do
    if text(listed[field]) ~= "" then
      return text(listed[field])
    end
  end

  return "the agent"
end

--- The agent pane of this workspace, out of `herdr agent list`: a pane herdr
--- names an agent for, in this workspace, other than this one. With several,
--- the first herdr names wins and the notification says which.
---@param listing string
---@param workspace string?
---@param me string?
---@return { pane: string, name: string }?, string?
function M.agent_in(listing, workspace, me)
  local ok, answer = pcall(vim.json.decode, listing)
  if not ok or type(answer) ~= "table" then
    return nil, "herdr agent list answered with something unreadable"
  end

  for _, listed in ipairs(vim.tbl_get(answer, "result", "agents") or {}) do
    local elsewhere = text(listed.workspace_id) ~= text(workspace)
    if text(listed.agent) ~= "" and text(listed.pane_id) ~= text(me) and not elsewhere then
      return { pane = text(listed.pane_id), name = named(listed) }
    end
  end

  return nil, "no agent pane in this workspace"
end

--- Put the brief in the registers and say where it went.
---
--- Both the unnamed register and the system one, so it can be pasted with `p`
--- inside Neovim and with the system paste anywhere else. A build with no
--- clipboard provider has no system register to write, which is said out loud:
--- a silent half-copy there would look exactly like a whole one.
---@param host table
---@param brief string
---@param because string? why the agent pane did not get it
local function copy(host, brief, because)
  local reached = host.copy(brief)
  local reason = because and (because .. "; ") or ""
  local where = reached and "the clipboard" or "the unnamed register, no clipboard provider"
  local said = ("%scopied the brief to %s, %s"):format(reason, where, NO_RECORD)

  if because then
    return message.warn(said)
  end

  message.say(said)
end

--- Send the brief to the agent pane, or to the clipboard when herdr cannot take
--- it.
---@param object table
---@param note string?
---@param host table
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

      -- Focus is a convenience once the text is delivered: a refused focus
      -- leaves the brief in the agent's input, so failing here would report a
      -- hand-off that did happen as one that did not.
      host.run({ "agent", "focus", agent.pane }, function() end)

      message.say(("sent to %s, %s"):format(agent.name, NO_RECORD))
    end)
  end)
end

--- The live host: the `herdr` CLI, the pane facts herdr puts in the
--- environment, and the registers.
---@return table
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

--- `S` on the list: the note box, then the hand-off. Nothing here happens on
--- its own, and an escaped box sends nothing at all.
function M.send()
  local object = require("damnit.list").object_under_cursor()
  if not object then
    return
  end

  vim.ui.input({ prompt = "Note: " }, function(note)
    if note == nil then
      return
    end

    M.hand_off(object, note, M.host())
  end)
end

return M
