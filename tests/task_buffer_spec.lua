local TESTS_DIR = arg[0]:match("(.*)/") or "."

local PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP = TESTS_DIR .. "/../plugin/damnit.lua"
dofile(PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP)

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local harness = dofile(TESTS_DIR .. "/helpers/task_buffer.lua")
local screen = dofile(TESTS_DIR .. "/helpers/screen.lua")
local task_buffer = require("damnit.task_buffer")

local OID = harness.OID

local REFUSAL_FOR_A_DEPENDENCY_THAT_WOULD_CLOSE_A_LOOP = table.concat({
  '{"error": {"kind": "refused", "rule": "cycle", ',
  '"message": "badb490 cannot depend on that: it would form a cycle through a9db854 -> badb490", ',
  '"oids": ["badb4903b653809e591c31118004e07de7c8183c", "a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77"]}}',
})

local REFUSAL_FOR_A_DUE_THAT_IS_NOT_A_DATE =
  '{"error": {"kind": "usage", "rule": null, "message": "--due: cannot read \\"whenever-ish\\" as a date", "oids": []}}'

local REFUSAL_FOR_A_MOVE_UNDER_ITS_OWN_CHILD = table.concat({
  '{"error": {"kind": "refused", "rule": "cycle", ',
  '"message": "badb490 cannot move under a9db854: that is its own child", ',
  '"oids": ["badb4903b653809e591c31118004e07de7c8183c", "a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77"]}}',
})

local EDIT_ARGV = ("edit %s --subject buy the oat milk --json"):format(OID)
local MV_ARGV = ("mv %s home/ --json"):format(OID)

return {
  ["reads the object with dam show and draws its frontmatter"] = function()
    harness.with_task(function(buf, fake)
      assert(
        vim.tbl_contains(fake_dam.argv_log(fake), "show " .. OID .. " --json"),
        vim.inspect(fake_dam.argv_log(fake))
      )
      assert(vim.bo[buf].filetype == "damtask", vim.bo[buf].filetype)
      assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "---")
      assert(
        vim.tbl_contains(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "subject: buy soy milk"),
        vim.inspect(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      )
    end)
  end,

  [":Dam task opens the same buffer the keymap does"] = function()
    harness.with_task(function(buf, fake)
      assert(
        vim.tbl_contains(fake_dam.argv_log(fake), "show " .. OID .. " --json"),
        vim.inspect(fake_dam.argv_log(fake))
      )
      assert(vim.bo[buf].filetype == "damtask", vim.bo[buf].filetype)
    end, {
      open = function(oid)
        vim.cmd("Dam task " .. oid)

        return nil
      end,
    })
  end,

  ["sends only the changed field and marks the buffer unmodified"] = function()
    harness.with_task(function(buf, fake)
      harness.set_field(buf, "subject", "buy the oat milk")

      assert(
        harness.argv_the_write_sent_or_nil(fake) == ("edit %s --subject buy the oat milk --json"):format(OID),
        "the wrong argv"
      )

      fake_dam.settle(function()
        return vim.bo[buf].modified == false
      end)
      assert(vim.bo[buf].modified == false, "a landed write leaves the buffer unmodified")
    end)
  end,

  ["sends a changed path as the container dam mv takes"] = function()
    harness.with_task(function(buf, fake)
      harness.set_field(buf, "path", "home/inbox/")

      assert(harness.argv_the_write_sent_or_nil(fake) == ("mv %s home/ --json"):format(OID), "the wrong argv")
    end)
  end,

  ["sends nothing when nothing changed"] = function()
    harness.with_task(function(buf, fake, notifications)
      assert(harness.argv_the_write_sent_or_nil(fake) == nil, "nothing was sent")
      assert(notifications[#notifications] == "damnit.nvim: nothing changed", vim.inspect(notifications))
      assert(vim.bo[buf].modified == false)
    end)
  end,

  ["keeps a sign column from the start, and draws this screen at 80x24 after priority: 9 is written"] = function()
    harness.with_task(function(buf, fake)
      assert(vim.wo[vim.fn.bufwinid(buf)].signcolumn == "yes:1", vim.wo[vim.fn.bufwinid(buf)].signcolumn)
      assert(vim.diagnostic.config(nil, task_buffer.NAMESPACE).virtual_text == true)
      screen.fix_size()
      harness.set_field(buf, "priority", "9")
      assert(harness.argv_the_write_sent_or_nil(fake) == nil, "a local refusal costs no call")

      screen.matches_golden("task_refusal")
    end)
  end,

  ["puts a local refusal on the line it is about, and sends nothing"] = function()
    harness.with_task(function(buf, fake)
      harness.set_field(buf, "priority", "9")

      assert(harness.argv_the_write_sent_or_nil(fake) == nil, "a local refusal costs no call")

      local found = harness.diagnostics(buf)
      assert(#found == 1, vim.inspect(found))
      assert(found[1].message:find("1, 2, 3 or 4", 1, true), found[1].message)
      assert(found[1].lnum > 0, "the priority line is not line one")
      assert(vim.bo[buf].modified == true, "the text stays where it can be fixed")
    end)
  end,

  ["puts dam's own refusal on line one and leaves the buffer modified"] = function()
    harness.with_task(function(buf, fake)
      harness.set_field(buf, "depends", "a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77")
      vim.env.DAMNIT_TEST_EXIT = "4"
      vim.env.DAMNIT_TEST_STDERR = REFUSAL_FOR_A_DEPENDENCY_THAT_WOULD_CLOSE_A_LOOP

      assert(harness.argv_the_write_sent_or_nil(fake) ~= nil, "the edit went out")
      fake_dam.settle(function()
        return #harness.diagnostics(buf) > 0
      end)

      local found = harness.diagnostics(buf)
      assert(found[1].message:find("form a cycle", 1, true), found[1].message)
      assert(found[1].lnum == 0, tostring(found[1].lnum))
      assert(vim.bo[buf].modified == true)
    end)
  end,

  ["a refused edit stops before the move, leaves the text as typed, and marks the line dam names"] = function()
    harness.with_task(function(buf, fake)
      local sent = harness.write_a_new_subject_and_path_then_settle(buf, fake)

      assert(vim.deep_equal(sent, { EDIT_ARGV }), vim.inspect(sent))
      assert(harness.field_line(buf, "subject") == "subject: buy the oat milk", harness.field_line(buf, "subject"))
      assert(vim.bo[buf].modified == true, "the text stays where it can be fixed")

      local found = harness.diagnostics(buf)
      assert(#found == 1, vim.inspect(found))
      assert(found[1].message == '--due: cannot read "whenever-ish" as a date', found[1].message)
      assert(found[1].lnum == harness.field_index(buf, "due") - 1, tostring(found[1].lnum))
    end, { fail = { edit = { exit = 2, stderr = REFUSAL_FOR_A_DUE_THAT_IS_NOT_A_DATE } } })
  end,

  ["a refused move after a landed edit leaves the buffer as typed and modified"] = function()
    harness.with_task(function(buf, fake)
      local sent = harness.write_a_new_subject_and_path_then_settle(buf, fake)

      assert(vim.deep_equal(sent, { EDIT_ARGV, MV_ARGV }), vim.inspect(sent))
      assert(harness.field_line(buf, "path") == "path: home/inbox/", harness.field_line(buf, "path"))
      assert(vim.bo[buf].modified == true, "the text stays where it can be fixed")

      local found = harness.diagnostics(buf)
      assert(#found == 1, vim.inspect(found))
      assert(found[1].message == "badb490 cannot move under a9db854: that is its own child", found[1].message)
    end, { fail = { mv = { exit = 4, stderr = REFUSAL_FOR_A_MOVE_UNDER_ITS_OWN_CHILD } } })
  end,

  ["an edit and a move that both land redraw the buffer once, from the move's answer"] = function()
    harness.with_task(function(buf, fake)
      local sent = harness.write_a_new_subject_and_path_then_settle(buf, fake)

      assert(vim.deep_equal(sent, { EDIT_ARGV, MV_ARGV }), vim.inspect(sent))
      assert(harness.field_line(buf, "subject") == "subject: buy soy milk", harness.field_line(buf, "subject"))
      assert(harness.field_line(buf, "path") == "path: home/inbox/", harness.field_line(buf, "path"))
      assert(vim.bo[buf].modified == false, "a landed write leaves the buffer unmodified")
      assert(#harness.diagnostics(buf) == 0, vim.inspect(harness.diagnostics(buf)))
    end)
  end,

  ["opening the same task twice focuses its one buffer and keeps the unsaved edit"] = function()
    harness.with_task(function(buf, fake)
      harness.set_field(buf, "subject", "buy the oat milk")
      vim.cmd("new")
      local empty = vim.api.nvim_get_current_buf()
      local calls = #fake_dam.argv_log(fake)

      local again = task_buffer.open(OID)

      assert(again == buf, ("a second open made buffer %d beside %d"):format(again, buf))
      assert(vim.api.nvim_get_current_buf() == buf, "the window already showing the task was not focused")
      assert(#vim.api.nvim_list_wins() == 2, "a window was opened or closed")
      assert(vim.api.nvim_win_get_buf(vim.fn.bufwinid(empty)) == empty, "the other window lost its buffer")
      assert(harness.field_line(buf, "subject") == "subject: buy the oat milk", harness.field_line(buf, "subject"))
      assert(#fake_dam.argv_log(fake) == calls, "the second open asked dam again")
    end)
  end,
}
