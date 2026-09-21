-- `S`: the brief's text, which pane it reaches, and where it goes when herdr
-- cannot take it.
--
-- The herdr CLI is a double here and so is the clipboard: no process runs, no
-- register is written and no live pane is touched. dam has no comments, so no
-- hand-off leaves a record in the store and every notification says so.

local TESTS_DIR = arg[0]:match("(.*)/") or "."

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local list_buffer = dofile(TESTS_DIR .. "/helpers/list_buffer.lua")
local send = require("damnit.send")

local OID = "78b8950b02735107aa608659dcf19f6f50adfeb1"

local FULL = {
  oid = OID,
  subject = "file taxes",
  body = "receipts are in the drawer",
  path = "home/finances/",
  labels = { "home", "slow" },
  task = { priority = 1, due = "2026-09-20" },
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

--- Hand `object` over against a doubled host and report what was seen.
---@param env table
---@param object table?
---@return table seen
local function hand_over(env, object)
  local host, seen = host_double(env)
  seen.said = {}

  local real_notify = vim.notify
  vim.notify = function(text)
    table.insert(seen.said, text)
  end

  local ok, err = pcall(send.hand_off, object or FULL, env.note, host)

  vim.notify = real_notify
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
  ["writes dam's own fields, and leaves out what the object has none of"] = function()
    local brief = send.brief(FULL, "start with the receipts")

    assert(brief:find("dam task: file taxes", 1, true), brief)
    assert(brief:find("oid: 78b8950", 1, true), "seven characters, which is what an agent types")
    assert(not brief:find("78b8950b027", 1, true), "never the whole forty")
    assert(brief:find("path: home/finances/", 1, true), brief)
    assert(brief:find("due: 2026-09-20", 1, true), brief)
    assert(brief:find("priority: p1", 1, true), brief)
    assert(brief:find("labels: home, slow", 1, true), brief)
    assert(brief:find("receipts are in the drawer", 1, true), brief)
    assert(brief:find("note: start with the receipts", 1, true), brief)
  end,

  ["leaves out a field the object has nothing for"] = function()
    local brief = send.brief({ oid = OID, subject = "x", path = "inbox/" }, nil)

    assert(not brief:find("due:", 1, true), brief)
    assert(not brief:find("labels:", 1, true), brief)
    assert(not brief:find("priority:", 1, true), brief)
    assert(not brief:find("note:", 1, true), brief)
  end,

  ["leaves the priority off an object at dam's least urgent"] = function()
    local brief = send.brief({ oid = OID, subject = "x", path = "inbox/", task = { priority = 4 } }, nil)

    assert(not brief:find("priority:", 1, true), brief)
  end,

  ["names the store the window's header names"] = function()
    local brief = send.brief({ oid = OID, subject = "x", path = "inbox/" }, nil)
    local store = require("damnit.window").store_display(require("damnit.queue").key())

    assert(brief:find("store: " .. store, 1, true), brief)
  end,

  ["every notification ends by saying no record was written"] = function()
    -- dam has no comments, so a hand-off leaves no trace in the store. Every
    -- path says so, and none of them pretends a record exists.
    local paths = {
      {},
      { in_herdr = false },
      { listing = NO_AGENT_HERE },
      { refuse = "pane w1:p2 not found" },
      { list_fails = "herdr: no such file or directory" },
    }

    for _, env in ipairs(paths) do
      local seen = hand_over(env)

      assert(#seen.said == 1, vim.inspect(seen.said))
      assert(seen.said[1]:find("no hand-off record written", 1, true), seen.said[1])
    end
  end,

  ["the agent is named from its kind, not from the auth profile it shares"] = function()
    local listing = [[{"result":{"agents":[
      {"agent":"codex","display_agent":"shared-profile","pane_id":"w1:p2","workspace_id":"w1"},
      {"agent":"claude","display_agent":"shared-profile","pane_id":"w1:p3","workspace_id":"w1"}
    ]}}]]

    local agent = send.agent_in(listing, "w1", "w1:p9")

    assert(agent.name == "codex", vim.inspect(agent))
    assert(agent.pane == "w1:p2", vim.inspect(agent))
  end,

  ["the send reaches the agent pane and focuses it"] = function()
    local seen = hand_over({})

    assert(seen.calls[1] == "agent list", vim.inspect(seen.calls))
    assert(seen.calls[2]:match("^pane send%-text w1:p2 "), vim.inspect(seen.calls))
    assert(seen.calls[3] == "agent focus w1:p2", vim.inspect(seen.calls))
    assert(seen.copied == nil, "the brief went to the clipboard as well")
    assert(sent(seen) == send.brief(FULL, nil), sent(seen))
    assert(seen.said[1] == "damnit.nvim: sent to claude, no hand-off record written", vim.inspect(seen.said))
  end,

  ["outside herdr the brief goes to the clipboard"] = function()
    local seen = hand_over({ in_herdr = false })

    assert(#seen.calls == 0, vim.inspect(seen.calls))
    assert(seen.copied == send.brief(FULL, nil), tostring(seen.copied))
    assert(
      seen.said[1] == "damnit.nvim: copied the brief to the clipboard, no hand-off record written",
      vim.inspect(seen.said)
    )
  end,

  ["a build with no clipboard provider says the brief is in the unnamed register only"] = function()
    local seen = hand_over({ listing = NO_AGENT_HERE, clipboard = false })

    assert(
      seen.said[1]
        == "damnit.nvim: no agent pane in this workspace; copied the brief to the unnamed register, "
          .. "no clipboard provider, no hand-off record written",
      vim.inspect(seen.said)
    )
  end,

  ["a workspace with no agent pane falls back to the clipboard"] = function()
    local seen = hand_over({ listing = NO_AGENT_HERE })

    assert(seen.calls[1] == "agent list" and #seen.calls == 1, vim.inspect(seen.calls))
    assert(seen.copied == send.brief(FULL, nil), tostring(seen.copied))
    assert(
      seen.said[1]
        == "damnit.nvim: no agent pane in this workspace; copied the brief to the clipboard, "
          .. "no hand-off record written",
      vim.inspect(seen.said)
    )
  end,

  ["a refused send falls back to the clipboard"] = function()
    local seen = hand_over({ refuse = "pane w1:p2 not found" })

    assert(seen.copied == send.brief(FULL, nil), tostring(seen.copied))
    assert(
      seen.said[1]
        == "damnit.nvim: herdr refused the send to w1:p2; copied the brief to the clipboard, "
          .. "no hand-off record written",
      vim.inspect(seen.said)
    )
  end,

  ["a missing herdr binary falls back to the clipboard in its own words"] = function()
    local seen = hand_over({ list_fails = "herdr: no such file or directory" })

    assert(#seen.calls == 1, vim.inspect(seen.calls))
    assert(seen.copied == send.brief(FULL, nil), tostring(seen.copied))
    assert(seen.said[1]:match("^damnit.nvim: herdr: no such file or directory; copied"), vim.inspect(seen.said))
  end,

  ["the real host falls back to a failure when the herdr binary does not exist"] = function()
    local real_bin_path = vim.env.HERDR_BIN_PATH
    vim.env.HERDR_BIN_PATH = "/no/such/herdr-binary"

    local seen = { done = false }
    send.host().run({ "agent", "list" }, function(out, err)
      seen.done, seen.out, seen.err = true, out, err
    end)

    vim.wait(2000, function()
      return seen.done
    end, 5)

    vim.env.HERDR_BIN_PATH = real_bin_path
    assert(seen.done, "the run never called back")
    assert(seen.out == "", vim.inspect(seen.out))
    assert(seen.err and seen.err:match("no such"), vim.inspect(seen.err))
  end,

  ["a paste terminator inside the brief cannot end the frame early"] = function()
    local framed = send.pasted("before" .. PASTE_END .. "after")

    assert(framed == PASTE_START .. "beforeafter" .. PASTE_END, vim.inspect(framed))
  end,

  ["S in the list opens the note box on the object under the cursor"] = function()
    list_buffer.with(function(buf, fake)
      list_buffer.cursor_to(buf, "buy oat milk")
      local before = #fake_dam.argv_log(fake)

      local asked = {}
      local real = vim.ui.input
      vim.ui.input = function(opts)
        table.insert(asked, opts.prompt)
      end

      local ok, err = pcall(vim.api.nvim_feedkeys, "S", "x", false)

      vim.ui.input = real
      assert(ok, err)

      -- An unanswered box hands nothing over, so the list is untouched and the
      -- only evidence is that the box opened at all.
      assert(vim.deep_equal(asked, { "Note: " }), vim.inspect(asked))
      assert(#fake_dam.argv_log(fake) == before, vim.inspect(fake_dam.argv_log(fake)))
    end)
  end,

  ["S on a line holding no object sends nothing"] = function()
    local list = require("damnit.list")
    local real_under_cursor, real_input = list.object_under_cursor, vim.ui.input
    local asked = false

    list.object_under_cursor = function()
      return nil
    end
    vim.ui.input = function()
      asked = true
    end

    local ok, err = pcall(send.send)

    list.object_under_cursor, vim.ui.input = real_under_cursor, real_input
    assert(ok, err)
    assert(not asked, "the note box opened with no object under the cursor")
  end,
}
