-- `S`: hand the task under the cursor to the agent, the way the herdr pane
-- does.
--
-- The brief is plain text because an agent pane is a shell, not a structure. In
-- herdr it goes into the agent pane's input as one bracketed paste and is never
-- submitted, so the operator reads it, adds to it and presses return
-- themselves. Outside herdr, and whenever herdr cannot take it, the same brief
-- goes to the clipboard and the notification says so.
--
-- The brief's wording is the herdr plugin's, character for character, so a hand
-- that learned one plugin reads the same hand-off in the other.

local M = {}

local client = require("damnit.client")
local format = require("damnit.list_format")

--- The frame `herdr pane send-text` writes the brief inside. A paste is
--- inserted verbatim by any input, where the raw bytes of a multi-line brief
--- would each be read as a key and a newline would submit it.
local PASTE_START = "\27[200~"
local PASTE_END = "\27[201~"

--- The app's own task page, built from the id: the v1 task object carries no
--- `url` field and this is the address the vendor documents in its place.
local TASK_URL = "https://app.todoist.com/app/task/%s"

---@param value any
---@return string
local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

---@param message string
---@param level integer?
local function say(message, level)
  vim.notify("damnit.nvim: " .. message, level or vim.log.levels.INFO)
end

--- The due date as its first ten characters, which are the date whether the
--- task carries a time or not. A task due by a phrase Todoist has not resolved
--- to a date keeps the phrase.
---@param task table
---@return string
local function due_of(task)
  local due = task.due
  if type(due) ~= "table" then
    return ""
  end

  local date = text(due.date)
  if date ~= "" then
    return date:sub(1, 10)
  end

  return text(due.string)
end

--- The task as the agent reads it: its title and URL, then whichever of the due
--- date, the priority and the labels the task has, then its description, then
--- the note. A field the task has nothing for is left out rather than written
--- empty, so the brief carries no line an agent has to discount.
---@param task table
---@param note string?
---@return string
function M.brief(task, note)
  local lines = {
    "Todoist task: " .. vim.trim(text(task.content)),
    "url: " .. TASK_URL:format(text(task.id)),
  }

  local due = due_of(task)
  if due ~= "" then
    lines[#lines + 1] = "due: " .. due
  end

  -- The API's scale runs the other way from the app's: 4 is the app's p1, and 1
  -- is no priority at all, which the brief leaves out.
  local priority = tonumber(task.priority) or 1
  if priority > 1 then
    lines[#lines + 1] = ("priority: p%d"):format(5 - priority)
  end

  local labels = format.labels_of(task)
  if #labels > 0 then
    lines[#lines + 1] = "labels: " .. table.concat(labels, ", ")
  end

  local description = vim.trim(text(task.description))
  if description ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = description
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

  say(reason .. "copied the brief to " .. where .. ", no hand-off comment written", because and vim.log.levels.WARN)
end

--- What the comment records. The agent is named rather than its pane, which
--- means nothing a day later; WHEN is the comment's own posted date, which
--- Todoist stamps.
---@param agent string
---@return string
local function handed_off(agent)
  return ("Handed to the agent %s from the Neovim Todoist list."):format(agent)
end

--- Send the brief, then record the hand-off on the task.
---
--- The comment is written only after the send succeeded, so a brief that went
--- to the clipboard instead leaves no record of a hand-off that did not happen.
--- A refused comment says so and does not pretend the send failed, because the
--- agent has the work either way.
---@param task table
---@param note string?
---@param host table
function M.hand_off(task, note, host)
  local brief = M.brief(task, note)

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

      client.add_comment(task.id, handed_off(agent.name), function(_, failure)
        if failure then
          return say(("sent to %s, comment refused"):format(agent.name), vim.log.levels.WARN)
        end

        say("sent to " .. agent.name)
      end)
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
      local binary = vim.env.HERDR_BIN_PATH
      if text(binary) == "" then
        binary = "herdr"
      end

      local command = vim.list_extend({ binary }, args)
      local ok, err = pcall(vim.system, command, { text = true }, function(result)
        local failure = result.code ~= 0 and vim.trim(("%s: %s"):format(binary, result.stderr or "")) or nil
        vim.schedule(function()
          done(result.stdout or "", failure)
        end)
      end)

      -- `vim.system` throws rather than calling back when the binary does not
      -- exist, so a stale `HERDR_BIN_PATH` would otherwise lose the brief.
      if not ok then
        vim.schedule(function()
          done("", vim.trim(("%s: %s"):format(binary, tostring(err))))
        end)
      end
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
  local task = require("damnit.list").task_under_cursor()
  if not task then
    return
  end

  vim.ui.input({ prompt = "Note: " }, function(note)
    if note == nil then
      return
    end

    M.hand_off(task, note, M.host())
  end)
end

return M
