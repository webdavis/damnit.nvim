-- `S`: the brief's text, which pane it reaches, and where it goes when herdr
-- cannot take it.
--
-- The herdr CLI is a double here and so is the clipboard: no process runs, no
-- register is written and no live pane is touched. The brief's wording is
-- asserted against the herdr plugin's own, so the two stay the same text.

local send = require("todoist.send")

local FULL_TASK = {
  id = "6X",
  content = "file taxes",
  priority = 4,
  labels = { "home", "slow" },
  due = { date = "2026-09-20T09:00:00Z" },
  description = "receipts are in the drawer",
}

--- What `herdr agent list` answers: one agent pane in this workspace, one in
--- another, and this pane itself, which herdr lists no agent for.
local LISTING = [[{"result":{"agents":[
  {"pane_id":"w1:p9","workspace_id":"w1"},
  {"agent":"codex","pane_id":"w2:p1","workspace_id":"w2"},
  {"agent":"claude","pane_id":"w1:p2","workspace_id":"w1"}
]}}]]

--- A workspace whose panes are all this pane and other workspaces' agents.
local NO_AGENT_HERE = [[{"result":{"agents":[
  {"pane_id":"w1:p9","workspace_id":"w1"},
  {"agent":"codex","pane_id":"w2:p1","workspace_id":"w2"}
]}}]]

local PASTE_START = "\27[200~"
local PASTE_END = "\27[201~"

--- A doubled host. `in_herdr` is the environment's answer, `listing` is what
--- `agent list` says, and `refuse` refuses every call after it.
---@param env table
---@return table host, table seen
local function host_double(env)
  local seen = { calls = {}, copied = nil }

  local host = {
    in_herdr = env.in_herdr ~= false,
    workspace = "w1",
    me = "w1:p9",
    run = function(args, done)
      table.insert(seen.calls, table.concat(args, " "))
      if args[1] == "agent" and args[2] == "list" then
        return done(env.listing or LISTING, env.list_fails)
      end

      done("", env.refuse)
    end,
    copy = function(brief)
      seen.copied = brief
      return env.clipboard ~= false
    end,
  }

  return host, seen
end

--- Hand `task` over against a doubled host and a doubled comment call.
---@param env table
---@param task table?
---@return table seen
local function hand_over(env, task)
  local client = require("todoist.client")
  local host, seen = host_double(env)
  seen.comments = {}
  seen.said = {}

  local real_comment, real_notify = client.add_comment, vim.notify
  client.add_comment = function(id, content, callback)
    table.insert(seen.comments, { id = id, content = content })
    callback(nil, env.comment_fails and { kind = "http", status = 400 } or nil)
  end
  vim.notify = function(message)
    table.insert(seen.said, message)
  end

  local ok, err = pcall(send.hand_off, task or FULL_TASK, env.note, host)

  client.add_comment, vim.notify = real_comment, real_notify
  assert(ok, err)

  return seen
end

--- The text of the one `pane send-text` call, with its paste framing taken off.
---@param seen table
---@return string
local function sent(seen)
  for _, call in ipairs(seen.calls) do
    local framed = call:match("^pane send%-text w1:p2 (.*)$")
    if framed then
      local body = framed:sub(#PASTE_START + 1, -(#PASTE_END + 1))
      assert(framed:sub(1, #PASTE_START) == PASTE_START, "no paste framing")
      assert(framed:sub(-#PASTE_END) == PASTE_END, "no paste framing")
      return body
    end
  end

  error("no send-text call in " .. vim.inspect(seen.calls))
end

return {
  ["a brief carries every field the task has"] = function()
    local seen = hand_over({ note = "start with the receipts" })

    assert(sent(seen) == table.concat({
      "Todoist task: file taxes",
      "url: https://app.todoist.com/app/task/6X",
      "due: 2026-09-20",
      "priority: p1",
      "labels: home, slow",
      "",
      "receipts are in the drawer",
      "",
      "note: start with the receipts",
    }, "\n"), sent(seen))
  end,

  ["a task with no description, due date or labels leaves those lines out"] = function()
    local seen = hand_over({ note = "  " }, { id = "6X", content = "think", priority = 1 })

    assert(sent(seen) == "Todoist task: think\nurl: https://app.todoist.com/app/task/6X", sent(seen))
  end,

  ["the url is built from the task id"] = function()
    local brief = send.brief({ id = "6cfCrabcdef", content = "think" })

    assert(brief:match("\nurl: https://app%.todoist%.com/app/task/6cfCrabcdef$"), brief)
  end,

  ["the agent is named from its kind, not from the auth profile it shares"] = function()
    local listing = [[{"result":{"agents":[
      {"agent":"codex","display_agent":"personal-backup","pane_id":"w1:p2","workspace_id":"w1"},
      {"agent":"claude","display_agent":"personal-backup","pane_id":"w1:p3","workspace_id":"w1"}
    ]}}]]

    local agent = send.agent_in(listing, "w1", "w1:p9")

    assert(agent.name == "codex", vim.inspect(agent))
    assert(agent.pane == "w1:p2", vim.inspect(agent))
  end,

  ["the send reaches the agent pane, focuses it, and comments on the task"] = function()
    local seen = hand_over({})

    assert(seen.calls[1] == "agent list", vim.inspect(seen.calls))
    assert(seen.calls[2]:match("^pane send%-text w1:p2 "), vim.inspect(seen.calls))
    assert(seen.calls[3] == "agent focus w1:p2", vim.inspect(seen.calls))
    assert(seen.copied == nil, "the brief went to the clipboard as well")
    assert(#seen.comments == 1 and seen.comments[1].id == "6X", vim.inspect(seen.comments))
    assert(
      seen.comments[1].content == "Handed to the agent claude from the Neovim Todoist list.",
      seen.comments[1].content
    )
    assert(seen.said[1] == "todoist.nvim: sent to claude", vim.inspect(seen.said))
  end,

  ["outside herdr the brief goes to the clipboard and no comment is written"] = function()
    local seen = hand_over({ in_herdr = false })

    assert(#seen.calls == 0, vim.inspect(seen.calls))
    assert(seen.copied == send.brief(FULL_TASK), seen.copied)
    assert(#seen.comments == 0, vim.inspect(seen.comments))
    assert(
      seen.said[1] == "todoist.nvim: copied the brief to the clipboard, no hand-off comment written",
      vim.inspect(seen.said)
    )
  end,

  ["a build with no clipboard provider says the brief is in the unnamed register only"] = function()
    local seen = hand_over({ listing = NO_AGENT_HERE, clipboard = false })

    assert(
      seen.said[1]
        == "todoist.nvim: no agent pane in this workspace; copied the brief to the unnamed register, "
          .. "no clipboard provider, no hand-off comment written",
      vim.inspect(seen.said)
    )
  end,

  ["a workspace with no agent pane falls back to the clipboard"] = function()
    local seen = hand_over({ listing = NO_AGENT_HERE })

    assert(seen.calls[1] == "agent list" and #seen.calls == 1, vim.inspect(seen.calls))
    assert(seen.copied == send.brief(FULL_TASK), tostring(seen.copied))
    assert(#seen.comments == 0, vim.inspect(seen.comments))
    assert(
      seen.said[1]
        == "todoist.nvim: no agent pane in this workspace; copied the brief to the clipboard, "
          .. "no hand-off comment written",
      vim.inspect(seen.said)
    )
  end,

  ["a refused send falls back to the clipboard and writes no comment"] = function()
    local seen = hand_over({ refuse = "herdr pane send-text failed: pane w1:p2 not found" })

    assert(seen.copied == send.brief(FULL_TASK), tostring(seen.copied))
    assert(#seen.comments == 0, vim.inspect(seen.comments))
    assert(
      seen.said[1]
        == "todoist.nvim: herdr refused the send to w1:p2; copied the brief to the clipboard, "
          .. "no hand-off comment written",
      vim.inspect(seen.said)
    )
  end,

  ["a missing herdr binary falls back to the clipboard in its own words"] = function()
    local seen = hand_over({ list_fails = "herdr: no such file or directory" })

    assert(#seen.calls == 1, vim.inspect(seen.calls))
    assert(seen.copied == send.brief(FULL_TASK), tostring(seen.copied))
    assert(seen.said[1]:match("^todoist.nvim: herdr: no such file or directory; copied"), vim.inspect(seen.said))
  end,

  ["a refused comment says so and does not claim the send failed"] = function()
    local seen = hand_over({ comment_fails = true })

    assert(seen.said[1] == "todoist.nvim: sent to claude, comment refused", vim.inspect(seen.said))
  end,

  ["a paste terminator inside the brief cannot end the frame early"] = function()
    local framed = send.pasted("before" .. PASTE_END .. "after")

    assert(framed == PASTE_START .. "beforeafter" .. PASTE_END, vim.inspect(framed))
  end,

  ["the hand-off comment is one POST to the comments endpoint"] = function()
    local client = require("todoist.client")
    local seen
    local real = client.request
    client.request = function(spec)
      seen = spec
    end

    client.add_comment("6X", "handed over", function() end)

    client.request = real
    assert(seen.method == "POST" and seen.path == "/comments", vim.inspect(seen))
    assert(seen.body.task_id == "6X" and seen.body.content == "handed over", vim.inspect(seen.body))
  end,

  ["S on a line holding no task sends nothing"] = function()
    local list = require("todoist.list")
    local real_under_cursor, real_input = list.task_under_cursor, vim.ui.input
    local asked = false

    list.task_under_cursor = function()
      return nil
    end
    vim.ui.input = function()
      asked = true
    end

    local ok, err = pcall(send.send)

    list.task_under_cursor, vim.ui.input = real_under_cursor, real_input
    assert(ok, err)
    assert(not asked, "the note box opened with no task under the cursor")
  end,
}
