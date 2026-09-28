local TESTS_DIR = arg[0]:match("(.*)/") or "."

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local hand_off = dofile(TESTS_DIR .. "/helpers/hand_off.lua")
local list_buffer = dofile(TESTS_DIR .. "/helpers/list_buffer.lua")
local send = require("damnit.send")

return {
  ["every notification ends by saying no record was written, since dam keeps no comments"] = function()
    local every_hand_off_path = {
      {},
      { in_herdr = false },
      { agent_list = hand_off.AGENT_LIST_WITH_NO_AGENT_HERE },
      { refusal_of_every_call_after_the_agent_list = "pane w1:p2 not found" },
      { agent_list_failure = "herdr: no such file or directory" },
    }

    for _, env in ipairs(every_hand_off_path) do
      local seen = hand_off.hand_over_to_a_double(env)

      assert(#seen.said == 1, vim.inspect(seen.said))
      assert(seen.said[1]:find("no hand-off record written", 1, true), seen.said[1])
    end
  end,

  ["the agent is named from its kind, not from the auth profile it shares"] = function()
    local listing = [[{"result":{"agents":[
      {"agent":"codex","display_agent":"shared-profile","pane_id":"w1:p2","workspace_id":"w1"},
      {"agent":"claude","display_agent":"shared-profile","pane_id":"w1:p3","workspace_id":"w1"}
    ]}}]]

    local agent = send.agent_in(listing, hand_off.THIS_WORKSPACE, hand_off.THIS_PANE_WHICH_HERDR_LISTS_NO_AGENT_FOR)

    assert(agent.name == "codex", vim.inspect(agent))
    assert(agent.pane == "w1:p2", vim.inspect(agent))
  end,

  ["the send reaches the agent pane and focuses it"] = function()
    local seen = hand_off.hand_over_to_a_double({})

    assert(seen.calls[1] == "agent list", vim.inspect(seen.calls))
    assert(seen.calls[2]:match("^pane send%-text w1:p2 "), vim.inspect(seen.calls))
    assert(seen.calls[3] == "agent focus w1:p2", vim.inspect(seen.calls))
    assert(seen.copied == nil, "the brief went to the clipboard as well")
    assert(
      hand_off.send_text_without_its_paste_framing(seen) == send.brief(hand_off.FULL, nil),
      hand_off.send_text_without_its_paste_framing(seen)
    )
    assert(seen.said[1] == "damnit.nvim: sent to claude, no hand-off record written", vim.inspect(seen.said))
  end,

  ["outside herdr the brief goes to the clipboard"] = function()
    local seen = hand_off.hand_over_to_a_double({ in_herdr = false })

    assert(#seen.calls == 0, vim.inspect(seen.calls))
    assert(seen.copied == send.brief(hand_off.FULL, nil), tostring(seen.copied))
    assert(
      seen.said[1] == "damnit.nvim: copied the brief to the clipboard, no hand-off record written",
      vim.inspect(seen.said)
    )
  end,

  ["a build with no clipboard provider says the brief is in the unnamed register only"] = function()
    local seen = hand_off.hand_over_to_a_double({
      agent_list = hand_off.AGENT_LIST_WITH_NO_AGENT_HERE,
      clipboard_provider = false,
    })

    assert(
      seen.said[1]
        == "damnit.nvim: no agent pane in this workspace; copied the brief to the unnamed register, "
          .. "no clipboard provider, no hand-off record written",
      vim.inspect(seen.said)
    )
  end,

  ["a workspace with no agent pane falls back to the clipboard"] = function()
    local seen = hand_off.hand_over_to_a_double({ agent_list = hand_off.AGENT_LIST_WITH_NO_AGENT_HERE })

    assert(seen.calls[1] == "agent list" and #seen.calls == 1, vim.inspect(seen.calls))
    assert(seen.copied == send.brief(hand_off.FULL, nil), tostring(seen.copied))
    assert(
      seen.said[1]
        == "damnit.nvim: no agent pane in this workspace; copied the brief to the clipboard, "
          .. "no hand-off record written",
      vim.inspect(seen.said)
    )
  end,

  ["a refused send falls back to the clipboard"] = function()
    local seen = hand_off.hand_over_to_a_double({ refusal_of_every_call_after_the_agent_list = "pane w1:p2 not found" })

    assert(seen.copied == send.brief(hand_off.FULL, nil), tostring(seen.copied))
    assert(
      seen.said[1]
        == "damnit.nvim: herdr refused the send to w1:p2; copied the brief to the clipboard, "
          .. "no hand-off record written",
      vim.inspect(seen.said)
    )
  end,

  ["a missing herdr binary falls back to the clipboard in its own words"] = function()
    local seen = hand_off.hand_over_to_a_double({ agent_list_failure = "herdr: no such file or directory" })

    assert(#seen.calls == 1, vim.inspect(seen.calls))
    assert(seen.copied == send.brief(hand_off.FULL, nil), tostring(seen.copied))
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

      assert(vim.deep_equal(asked, { "Note: " }), "the box opening is the only evidence: " .. vim.inspect(asked))
      assert(
        #fake_dam.argv_log(fake) == before,
        "an unanswered box hands nothing over: " .. vim.inspect(fake_dam.argv_log(fake))
      )
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
