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
}
