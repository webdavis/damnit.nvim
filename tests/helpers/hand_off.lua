local M = {}

local send = require("damnit.send")

M.OID = "78b8950b02735107aa608659dcf19f6f50adfeb1"

M.FULL = {
  oid = M.OID,
  subject = "file taxes",
  body = "receipts are in the drawer",
  path = "home/finances/",
  labels = { "home", "slow" },
  task = { priority = 1, due = "2026-09-20" },
}

M.THIS_WORKSPACE = "w1"
M.THIS_PANE_WHICH_HERDR_LISTS_NO_AGENT_FOR = "w1:p9"

M.AGENT_LIST_WITH_AN_AGENT_HERE = [[{"result":{"agents":[
  {"pane_id":"w1:p9","workspace_id":"w1"},
  {"agent":"codex","pane_id":"w2:p1","workspace_id":"w2"},
  {"agent":"claude","pane_id":"w1:p2","workspace_id":"w1"}
]}}]]

M.AGENT_LIST_WITH_NO_AGENT_HERE = [[{"result":{"agents":[
  {"pane_id":"w1:p9","workspace_id":"w1"},
  {"agent":"codex","pane_id":"w2:p1","workspace_id":"w2"}
]}}]]

M.PASTE_START = "\27[200~"
M.PASTE_END = "\27[201~"

local function herdr_and_clipboard_double(env)
  local seen = { calls = {}, copied = nil }

  local host = {
    in_herdr = env.in_herdr ~= false,
    workspace = M.THIS_WORKSPACE,
    me = M.THIS_PANE_WHICH_HERDR_LISTS_NO_AGENT_FOR,
    run = function(args, done)
      table.insert(seen.calls, table.concat(args, " "))
      if args[1] == "agent" and args[2] == "list" then
        return done(env.agent_list or M.AGENT_LIST_WITH_AN_AGENT_HERE, env.agent_list_failure)
      end

      done("", env.refusal_of_every_call_after_the_agent_list)
    end,
    copy = function(brief)
      seen.copied = brief
      return env.clipboard_provider ~= false
    end,
  }

  return host, seen
end

function M.hand_over_to_a_double(env, object)
  local host, seen = herdr_and_clipboard_double(env)
  seen.said = {}

  local real_notify = vim.notify
  vim.notify = function(text)
    table.insert(seen.said, text)
  end

  local ok, err = pcall(send.hand_off, object or M.FULL, env.note, host)

  vim.notify = real_notify
  assert(ok, err)

  return seen
end

function M.send_text_without_its_paste_framing(seen)
  for _, call in ipairs(seen.calls) do
    local framed = call:match("^pane send%-text w1:p2 (.*)$")
    if framed then
      local body = framed:sub(#M.PASTE_START + 1, -(#M.PASTE_END + 1))
      assert(framed:sub(1, #M.PASTE_START) == M.PASTE_START, "no paste framing")
      assert(framed:sub(-#M.PASTE_END) == M.PASTE_END, "no paste framing")
      return body
    end
  end

  error("no send-text call in " .. vim.inspect(seen.calls))
end

return M
