local with_dam = require("helpers.harness").with_dam
local harness = require("helpers.harness")

local fake_process = require("helpers.fake_process")
local list_buffer = require("helpers.list_buffer")
local said = require("helpers.said")

local function indent_of(line)
  return #line:match("^%s*")
end

return {
  ["asks dam for every open object and draws one line each"] = function()
    with_dam(list_buffer.opts(), function(dam)
      assert(
        vim.tbl_contains(fake_process.argv_log(dam.fake), "ls !done --json"),
        vim.inspect(fake_process.argv_log(dam.fake))
      )

      local body = table.concat(vim.api.nvim_buf_get_lines(dam.buf, 0, -1, false), "\n")
      assert(body:find("parent", 1, true), body)
      assert(body:find("child", 1, true), body)
      assert(body:find("buy oat milk", 1, true), body)
    end)
  end,

  ["leaves a finished object out of the list that calls itself all open tasks"] = function()
    with_dam(list_buffer.opts({ fixtures = harness.fixtures("open_and_done") }), function(dam)
      local lines = vim.api.nvim_buf_get_lines(dam.buf, 0, -1, false)
      local body = table.concat(lines, "\n")

      assert(lines[1] == "dam: all open tasks", lines[1])
      assert(body:find("buy oat milk", 1, true), body)
      assert(not body:find("took out the bins", 1, true), body)
    end)
  end,

  ["indents a child under the object whose path it extends"] = function()
    with_dam(list_buffer.opts(), function(dam)
      local lines = vim.api.nvim_buf_get_lines(dam.buf, 0, -1, false)
      local parent, child = nil, nil

      for index, line in ipairs(lines) do
        if line:find("- parent", 1, true) then
          parent = index
        end
        if line:find("- child", 1, true) then
          child = index
        end
      end

      assert(parent and child and child > parent, vim.inspect(lines))
      assert(indent_of(lines[child]) > indent_of(lines[parent]), vim.inspect(lines))
    end)
  end,

  ["sends the declared query rather than the view's name"] = function()
    with_dam(list_buffer.opts({ views = { today = "due:today | overdue" }, name = "today" }), function(dam)
      assert(
        vim.tbl_contains(fake_process.argv_log(dam.fake), "ls due:today | overdue --json"),
        vim.inspect(fake_process.argv_log(dam.fake))
      )
    end)
  end,

  ["draws dam's own wording in the buffer when it refused the view"] = function()
    with_dam(
      list_buffer.opts({
        views = { nonsense = "due:::" },
        name = "nonsense",
        exit = 1,
        stderr = '{"error": {"kind": "parse", "rule": null, "message": "unexpected nonsense in query", "oids": []}}',
      }),
      function(dam)
        local body = table.concat(vim.api.nvim_buf_get_lines(dam.buf, 0, -1, false), "\n")

        assert(body:find("dam refused this view:", 1, true), body)
        assert(body:find("unexpected nonsense in query", 1, true), body)
      end
    )
  end,

  ["R re-reads the view, and za folds a subtree away"] = function()
    with_dam(list_buffer.opts(), function(dam)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("R", "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before
      end)
      assert(
        fake_process.argv_log(dam.fake)[before + 1] == "ls !done --json",
        vim.inspect(fake_process.argv_log(dam.fake))
      )

      fake_process.settle(function()
        return table.concat(vim.api.nvim_buf_get_lines(dam.buf, 0, -1, false), "\n"):find("- child", 1, true) ~= nil
      end)
      local full = vim.api.nvim_buf_line_count(dam.buf)
      list_buffer.cursor_to(dam.buf, "- parent")
      vim.api.nvim_feedkeys("za", "x", false)

      assert(vim.api.nvim_buf_line_count(dam.buf) < full, "a fold here is a line never drawn, not a line hidden")
      assert(
        not table.concat(vim.api.nvim_buf_get_lines(dam.buf, 0, -1, false), "\n"):find("- child", 1, true),
        "the child is still drawn"
      )
    end)
  end,

  ["<CR> opens the object on the line as a task buffer"] = function()
    with_dam(list_buffer.opts(), function(dam)
      list_buffer.cursor_to(dam.buf, "buy oat milk")
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before
      end)

      assert(
        fake_process.argv_log(dam.fake)[before + 1] == "show c30414962aa4332b6e5dfc2e0360e2b328735efe --json",
        vim.inspect(fake_process.argv_log(dam.fake))
      )
    end)
  end,

  ["u outside the completed history refuses and sends nothing"] = function()
    with_dam(list_buffer.opts(), function(dam)
      list_buffer.cursor_to(dam.buf, "buy oat milk")
      local before = #fake_process.argv_log(dam.fake)

      vim.api.nvim_feedkeys("u", "x", false)
      fake_process.drain()

      assert(
        #fake_process.argv_log(dam.fake) == before,
        "a plain dam ls holds completed objects too, and reopening one clears completed_at for good: "
          .. vim.inspect(fake_process.argv_log(dam.fake))
      )
      assert(
        said.whole(dam.said[#dam.said], "damnit.nvim: u reopens in the completed history; X reopens an object here"),
        vim.inspect(dam.said)
      )
    end)
  end,

  ["gd on an object with no location in its body says so"] = function()
    with_dam(list_buffer.opts(), function(dam)
      list_buffer.cursor_to(dam.buf, "buy oat milk")
      vim.api.nvim_feedkeys("gd", "x", false)

      assert(dam.said[#dam.said] == "damnit.nvim: this task has no location in its body", vim.inspect(dam.said))
    end)
  end,

  ["<CR> on the title says there is no object there and opens nothing"] = function()
    with_dam(list_buffer.opts(), function(dam)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)

      assert(#fake_process.argv_log(dam.fake) == before, vim.inspect(fake_process.argv_log(dam.fake)))
      assert(dam.said[#dam.said] == "damnit.nvim: no object on this line", vim.inspect(dam.said))
    end)
  end,
}
