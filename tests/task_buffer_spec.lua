local TESTS_DIR = arg[0]:match("(.*)/") or "."

local PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP = TESTS_DIR .. "/../plugin/damnit.lua"
dofile(PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP)

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local queue = require("damnit.queue")
local task_buffer = require("damnit.task_buffer")

local OID = "badb4903b653809e591c31118004e07de7c8183c"

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

local function with_task(run, opts)
  local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full", fail = (opts or {}).fail })
  queue.reset()

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local open = (opts or {}).open or task_buffer.open
  local buf = open(OID) or vim.api.nvim_get_current_buf()
  fake_dam.settle(function()
    return vim.api.nvim_buf_line_count(buf) > 1
  end)

  local ok, err = pcall(run, buf, fake, notifications)

  vim.notify = real
  vim.cmd("silent! %bwipeout!")
  queue.reset()
  fake_dam.remove(fake)

  assert(ok, err)
end

local function set_field(buf, key, value)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:match("^" .. key .. ":") then
      vim.api.nvim_buf_set_lines(buf, index - 1, index, false, { ("%s: %s"):format(key, value) })

      return
    end
  end

  error("no " .. key .. " line in the buffer")
end

local function argv_the_write_sent_or_nil(fake)
  local before = #fake_dam.argv_log(fake)
  vim.cmd("write")

  if not fake_dam.wait_long_enough_to_catch_a_stray_call(fake, before) then
    return nil
  end

  return fake_dam.argv_log(fake)[before + 1]
end

local function diagnostics(buf)
  return vim.diagnostic.get(buf, { namespace = task_buffer.NAMESPACE })
end

local function field_line(buf, key)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if vim.startswith(line, key .. ":") then
      return line
    end
  end
end

local function write_a_new_subject_and_path_then_settle(buf, fake)
  set_field(buf, "subject", "buy the oat milk")
  set_field(buf, "path", "home/inbox/")

  local before = #fake_dam.argv_log(fake)
  vim.cmd("write")
  fake_dam.settle(function()
    return #diagnostics(buf) > 0 or vim.bo[buf].modified == false
  end)
  fake_dam.wait_long_enough_to_catch_a_stray_call(fake, #fake_dam.argv_log(fake))

  return vim.list_slice(fake_dam.argv_log(fake), before + 1)
end

return {
  ["reads the object with dam show and draws its frontmatter"] = function()
    with_task(function(buf, fake)
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
    with_task(function(buf, fake)
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
    with_task(function(buf, fake)
      set_field(buf, "subject", "buy the oat milk")

      assert(
        argv_the_write_sent_or_nil(fake) == ("edit %s --subject buy the oat milk --json"):format(OID),
        "the wrong argv"
      )

      fake_dam.settle(function()
        return vim.bo[buf].modified == false
      end)
      assert(vim.bo[buf].modified == false, "a landed write leaves the buffer unmodified")
    end)
  end,

  ["sends a changed path as the container dam mv takes"] = function()
    with_task(function(buf, fake)
      set_field(buf, "path", "home/inbox/")

      assert(argv_the_write_sent_or_nil(fake) == ("mv %s home/ --json"):format(OID), "the wrong argv")
    end)
  end,

  ["sends nothing when nothing changed"] = function()
    with_task(function(buf, fake, notifications)
      assert(argv_the_write_sent_or_nil(fake) == nil, "nothing was sent")
      assert(notifications[#notifications] == "damnit.nvim: nothing changed", vim.inspect(notifications))
      assert(vim.bo[buf].modified == false)
    end)
  end,

  ["puts a local refusal on the line it is about, and sends nothing"] = function()
    with_task(function(buf, fake)
      set_field(buf, "priority", "9")

      assert(argv_the_write_sent_or_nil(fake) == nil, "a local refusal costs no call")

      local found = diagnostics(buf)
      assert(#found == 1, vim.inspect(found))
      assert(found[1].message:find("1, 2, 3 or 4", 1, true), found[1].message)
      assert(found[1].lnum > 0, "the priority line is not line one")
      assert(vim.bo[buf].modified == true, "the text stays where it can be fixed")
    end)
  end,

  ["puts dam's own refusal on line one and leaves the buffer modified"] = function()
    with_task(function(buf, fake)
      set_field(buf, "depends", "a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77")
      vim.env.DAMNIT_TEST_EXIT = "4"
      vim.env.DAMNIT_TEST_STDERR = REFUSAL_FOR_A_DEPENDENCY_THAT_WOULD_CLOSE_A_LOOP

      assert(argv_the_write_sent_or_nil(fake) ~= nil, "the edit went out")
      fake_dam.settle(function()
        return #diagnostics(buf) > 0
      end)

      local found = diagnostics(buf)
      assert(found[1].message:find("form a cycle", 1, true), found[1].message)
      assert(found[1].lnum == 0, tostring(found[1].lnum))
      assert(vim.bo[buf].modified == true)
    end)
  end,

  ["a refused edit stops before the move and leaves the text as typed"] = function()
    with_task(function(buf, fake)
      local sent = write_a_new_subject_and_path_then_settle(buf, fake)

      assert(vim.deep_equal(sent, { EDIT_ARGV }), vim.inspect(sent))
      assert(field_line(buf, "subject") == "subject: buy the oat milk", field_line(buf, "subject"))
      assert(vim.bo[buf].modified == true, "the text stays where it can be fixed")

      local found = diagnostics(buf)
      assert(#found == 1, vim.inspect(found))
      assert(found[1].message == '--due: cannot read "whenever-ish" as a date', found[1].message)
    end, { fail = { edit = { exit = 2, stderr = REFUSAL_FOR_A_DUE_THAT_IS_NOT_A_DATE } } })
  end,

  ["a refused move after a landed edit leaves the buffer as typed and modified"] = function()
    with_task(function(buf, fake)
      local sent = write_a_new_subject_and_path_then_settle(buf, fake)

      assert(vim.deep_equal(sent, { EDIT_ARGV, MV_ARGV }), vim.inspect(sent))
      assert(field_line(buf, "path") == "path: home/inbox/", field_line(buf, "path"))
      assert(vim.bo[buf].modified == true, "the text stays where it can be fixed")

      local found = diagnostics(buf)
      assert(#found == 1, vim.inspect(found))
      assert(found[1].message == "badb490 cannot move under a9db854: that is its own child", found[1].message)
    end, { fail = { mv = { exit = 4, stderr = REFUSAL_FOR_A_MOVE_UNDER_ITS_OWN_CHILD } } })
  end,

  ["an edit and a move that both land redraw the buffer once, from the move's answer"] = function()
    with_task(function(buf, fake)
      local sent = write_a_new_subject_and_path_then_settle(buf, fake)

      assert(vim.deep_equal(sent, { EDIT_ARGV, MV_ARGV }), vim.inspect(sent))
      assert(field_line(buf, "subject") == "subject: buy soy milk", field_line(buf, "subject"))
      assert(field_line(buf, "path") == "path: home/inbox/", field_line(buf, "path"))
      assert(vim.bo[buf].modified == false, "a landed write leaves the buffer unmodified")
      assert(#diagnostics(buf) == 0, vim.inspect(diagnostics(buf)))
    end)
  end,
}
