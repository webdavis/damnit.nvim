local with_dam = require("helpers.harness").with_dam
local app = require("damnit").app()
local fake_process = require("helpers.fake_process")
local harness = require("helpers.harness")
local task = require("helpers.task_buffer")
local task_buffer = require("damnit.task_buffer")

local function open_in_a_tab_then_close_it_before_the_answer(dam)
  dam.fake.hold = true
  vim.cmd("tabnew")
  local buf = task_buffer.open(app, task.OID)
  vim.cmd("tabclose")
  fake_process.drain()

  return buf
end

local function write_an_edit_and_a_move_then_close_the_tab_before_the_answers(dam)
  vim.cmd("tabnew")
  local buf = task_buffer.open(app, task.OID)
  fake_process.drain()
  task.set_field(buf, "subject", "buy the oat milk")
  task.set_field(buf, "path", "home/inbox/")
  dam.fake.hold = true
  vim.cmd("write")
  vim.cmd("tabclose")
  dam.fake.release()
  fake_process.drain()

  return buf
end

return {
  ["a show answer landing after its tab closed draws nothing and leaves no buffer"] = function()
    with_dam({ fixtures = harness.fixtures("full") }, function(dam)
      local buf = open_in_a_tab_then_close_it_before_the_answer(dam)

      assert(not vim.api.nvim_buf_is_valid(buf), "the late answer drew into a buffer no window shows")
      assert(#dam.said == 0, vim.inspect(dam.said))
    end)
  end,

  ["opening the object again after a late answer reads it afresh"] = function()
    with_dam({ fixtures = harness.fixtures("full") }, function(dam)
      open_in_a_tab_then_close_it_before_the_answer(dam)

      local buf = task_buffer.open(app, task.OID)
      fake_process.drain()

      assert(task.field_line(buf, "subject") == "subject: buy soy milk", task.field_line(buf, "subject"))
    end)
  end,

  ["an edit and move answer landing after its tab closed keeps the buffer undrawn and saved"] = function()
    with_dam({ fixtures = harness.fixtures("full") }, function(dam)
      local buf = write_an_edit_and_a_move_then_close_the_tab_before_the_answers(dam)

      assert(vim.api.nvim_buf_is_valid(buf), "the written buffer was dropped")
      assert(task.field_line(buf, "subject") == "subject: buy the oat milk", task.field_line(buf, "subject"))
      assert(vim.bo[buf].modified == false, "the written buffer still reads as unsaved")
    end)
  end,

  ["the late edit and move answer is drawn once the buffer is shown again"] = function()
    with_dam({ fixtures = harness.fixtures("full") }, function(dam)
      write_an_edit_and_a_move_then_close_the_tab_before_the_answers(dam)

      local buf = task_buffer.open(app, task.OID)

      assert(task.field_line(buf, "path") == "path: home/inbox/", task.field_line(buf, "path"))
      assert(task.field_line(buf, "subject") == "subject: buy soy milk", "the move's answer is the one drawn")
    end)
  end,
}
