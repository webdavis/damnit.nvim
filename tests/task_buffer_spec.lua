local with_dam = require("helpers.harness").with_dam
local app = require("damnit").app()
local TESTS_DIR = require("helpers.paths").TESTS

local PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP = TESTS_DIR .. "/../plugin/damnit.lua"
dofile(PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP)

local fake_process = require("helpers.fake_process")
local task = require("helpers.task_buffer")
local screen = require("helpers.screen")
local task_buffer = require("damnit.task_buffer")

local OID = task.OID

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
local MV_ARGV = ("mv %s home/inbox/ --json"):format(OID)

local function through_the_command(oid)
  vim.cmd("Dam task " .. oid)
end

return {
  ["reads the object with dam show and draws its frontmatter"] = function()
    with_dam(task.opts(), function(dam)
      assert(
        vim.tbl_contains(fake_process.argv_log(dam.fake), "show " .. OID .. " --json"),
        vim.inspect(fake_process.argv_log(dam.fake))
      )
      assert(vim.bo[dam.buf].filetype == "damtask", vim.bo[dam.buf].filetype)
      assert(vim.api.nvim_buf_get_lines(dam.buf, 0, 1, false)[1] == "---")
      assert(
        vim.tbl_contains(vim.api.nvim_buf_get_lines(dam.buf, 0, -1, false), "subject: buy soy milk"),
        vim.inspect(vim.api.nvim_buf_get_lines(dam.buf, 0, -1, false))
      )
    end)
  end,

  [":Dam task opens the same buffer the keymap does"] = function()
    with_dam(task.opts({ open = through_the_command }), function(dam)
      assert(
        vim.tbl_contains(fake_process.argv_log(dam.fake), "show " .. OID .. " --json"),
        vim.inspect(fake_process.argv_log(dam.fake))
      )
      assert(vim.bo[dam.buf].filetype == "damtask", vim.bo[dam.buf].filetype)
    end)
  end,

  ["sends only the changed field and marks the buffer unmodified"] = function()
    with_dam(task.opts(), function(dam)
      task.set_field(dam.buf, "subject", "buy the oat milk")

      assert(
        task.argv_the_write_sent_or_nil(dam.fake) == ("edit %s --subject buy the oat milk --json"):format(OID),
        "the wrong argv"
      )

      fake_process.settle(function()
        return vim.bo[dam.buf].modified == false
      end)
      assert(vim.bo[dam.buf].modified == false, "a landed write leaves the buffer unmodified")
    end)
  end,

  ["sends a changed path to dam mv as typed, and the object ends there"] = function()
    with_dam(task.opts(), function(dam)
      task.set_field(dam.buf, "path", "home/")

      assert(task.argv_the_write_sent_or_nil(dam.fake) == ("mv %s home/ --json"):format(OID), "the wrong argv")
      fake_process.settle(function()
        return task.field_line(dam.buf, "path") == "path: home/"
      end)
    end)
  end,

  ["sends nothing when nothing changed"] = function()
    with_dam(task.opts(), function(dam)
      assert(task.argv_the_write_sent_or_nil(dam.fake) == nil, "nothing was sent")
      assert(dam.said[#dam.said] == "damnit.nvim: nothing changed", vim.inspect(dam.said))
      assert(vim.bo[dam.buf].modified == false)
    end)
  end,

  ["keeps a sign column from the start, and draws this screen at 80x24 after priority: 9 is written"] = function()
    with_dam(task.opts(), function(dam)
      assert(vim.wo[vim.fn.bufwinid(dam.buf)].signcolumn == "yes:1", vim.wo[vim.fn.bufwinid(dam.buf)].signcolumn)
      assert(vim.diagnostic.config(nil, task_buffer.NAMESPACE).virtual_text == true)
      screen.fix_size()
      task.set_field(dam.buf, "priority", "9")
      assert(task.argv_the_write_sent_or_nil(dam.fake) == nil, "a local refusal costs no call")

      screen.matches_golden("task_refusal")
    end)
  end,

  ["puts a local refusal on the line it is about, and sends nothing"] = function()
    with_dam(task.opts(), function(dam)
      task.set_field(dam.buf, "priority", "9")

      assert(task.argv_the_write_sent_or_nil(dam.fake) == nil, "a local refusal costs no call")

      local found = task.diagnostics(dam.buf)
      assert(#found == 1, vim.inspect(found))
      assert(found[1].message:find("1, 2, 3 or 4", 1, true), found[1].message)
      assert(found[1].lnum > 0, "the priority line is not line one")
      assert(vim.bo[dam.buf].modified == true, "the text stays where it can be fixed")
    end)
  end,

  ["puts dam's own refusal on line one and leaves the buffer modified"] = function()
    with_dam(task.opts(), function(dam)
      task.set_field(dam.buf, "depends", "a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77")
      dam.fake.exit = 4
      dam.fake.stderr = REFUSAL_FOR_A_DEPENDENCY_THAT_WOULD_CLOSE_A_LOOP

      assert(task.argv_the_write_sent_or_nil(dam.fake) ~= nil, "the edit went out")
      fake_process.settle(function()
        return #task.diagnostics(dam.buf) > 0
      end)

      local found = task.diagnostics(dam.buf)
      assert(found[1].message:find("form a cycle", 1, true), found[1].message)
      assert(found[1].lnum == 0, tostring(found[1].lnum))
      assert(vim.bo[dam.buf].modified == true)
    end)
  end,

  ["a refused edit stops before the move, leaves the text as typed, and marks the line dam names"] = function()
    with_dam(task.opts({ fail = { edit = { exit = 2, stderr = REFUSAL_FOR_A_DUE_THAT_IS_NOT_A_DATE } } }), function(dam)
      local sent = task.write_a_new_subject_and_path_then_settle(dam.buf, dam.fake)

      assert(vim.deep_equal(sent, { EDIT_ARGV }), vim.inspect(sent))
      assert(task.field_line(dam.buf, "subject") == "subject: buy the oat milk", task.field_line(dam.buf, "subject"))
      assert(vim.bo[dam.buf].modified == true, "the text stays where it can be fixed")

      local found = task.diagnostics(dam.buf)
      assert(#found == 1, vim.inspect(found))
      assert(found[1].message == '--due: cannot read "whenever-ish" as a date', found[1].message)
      assert(found[1].lnum == task.field_index(dam.buf, "due") - 1, tostring(found[1].lnum))
    end)
  end,

  ["a refused move after a landed edit leaves the buffer as typed and modified"] = function()
    with_dam(task.opts({ fail = { mv = { exit = 4, stderr = REFUSAL_FOR_A_MOVE_UNDER_ITS_OWN_CHILD } } }), function(dam)
      local sent = task.write_a_new_subject_and_path_then_settle(dam.buf, dam.fake)

      assert(vim.deep_equal(sent, { EDIT_ARGV, MV_ARGV }), vim.inspect(sent))
      assert(task.field_line(dam.buf, "path") == "path: home/inbox/", task.field_line(dam.buf, "path"))
      assert(vim.bo[dam.buf].modified == true, "the text stays where it can be fixed")

      local found = task.diagnostics(dam.buf)
      assert(#found == 1, vim.inspect(found))
      assert(found[1].message == "badb490 cannot move under a9db854: that is its own child", found[1].message)
    end)
  end,

  ["an edit and a move that both land redraw the buffer once, from the move's answer"] = function()
    with_dam(task.opts(), function(dam)
      local sent = task.write_a_new_subject_and_path_then_settle(dam.buf, dam.fake)

      assert(vim.deep_equal(sent, { EDIT_ARGV, MV_ARGV }), vim.inspect(sent))
      assert(task.field_line(dam.buf, "subject") == "subject: buy soy milk", task.field_line(dam.buf, "subject"))
      assert(task.field_line(dam.buf, "path") == "path: home/inbox/", task.field_line(dam.buf, "path"))
      assert(vim.bo[dam.buf].modified == false, "a landed write leaves the buffer unmodified")
      assert(#task.diagnostics(dam.buf) == 0, vim.inspect(task.diagnostics(dam.buf)))
    end)
  end,

  ["opening the same task twice focuses its one buffer and keeps the unsaved edit"] = function()
    with_dam(task.opts(), function(dam)
      task.set_field(dam.buf, "subject", "buy the oat milk")
      vim.cmd("new")
      local empty = vim.api.nvim_get_current_buf()
      local calls = #fake_process.argv_log(dam.fake)

      local again = task_buffer.open(app, OID)

      assert(again == dam.buf, ("a second open made buffer %d beside %d"):format(again, dam.buf))
      assert(vim.api.nvim_get_current_buf() == dam.buf, "the window already showing the task was not focused")
      assert(#vim.api.nvim_list_wins() == 2, "a window was opened or closed")
      assert(vim.api.nvim_win_get_buf(vim.fn.bufwinid(empty)) == empty, "the other window lost its buffer")
      assert(task.field_line(dam.buf, "subject") == "subject: buy the oat milk", task.field_line(dam.buf, "subject"))
      assert(#fake_process.argv_log(dam.fake) == calls, "the second open asked dam again")
    end)
  end,
}
