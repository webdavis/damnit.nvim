-- The list buffer: what it asks dam for, what it draws, and what it refuses.

local TESTS_DIR = arg[0]:match("(.*)/") or "."

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local list_buffer = dofile(TESTS_DIR .. "/helpers/list_buffer.lua")
local damnit = require("damnit")

--- The indent one line carries.
---@param line string
---@return integer
local function indent_of(line)
  return #line:match("^%s*")
end

return {
  ["asks dam for every open object and draws one line each"] = function()
    list_buffer.with(function(buf, fake)
      assert(vim.tbl_contains(fake_dam.argv_log(fake), "ls --json"), vim.inspect(fake_dam.argv_log(fake)))

      local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      assert(body:find("parent", 1, true), body)
      assert(body:find("child", 1, true), body)
      assert(body:find("buy oat milk", 1, true), body)
    end)
  end,

  ["indents a child under the object whose path it extends"] = function()
    list_buffer.with(function(buf)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
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
    list_buffer.with(function(_, fake)
      assert(
        vim.tbl_contains(fake_dam.argv_log(fake), "ls due:today | overdue --json"),
        vim.inspect(fake_dam.argv_log(fake))
      )
    end, { views = { today = "due:today | overdue" }, name = "today" })
  end,

  ["reports dam's own wording for a name it cannot parse, and remembers it"] = function()
    list_buffer.with(function(_, fake, notifications)
      assert(notifications[#notifications] == "unexpected nonsense in query", vim.inspect(notifications))

      local before = #fake_dam.argv_log(fake)
      damnit.open("nonsense")

      assert(#fake_dam.argv_log(fake) == before, "the second attempt costs no call")
    end, {
      name = "nonsense",
      exit = 1,
      stderr = '{"error": {"kind": "parse", "rule": null, "message": "unexpected nonsense in query", "oids": []}}',
    })
  end,

  ["keeps a probed name when the failure said nothing about it"] = function()
    list_buffer.with(function(_, fake)
      local before = #fake_dam.argv_log(fake)
      damnit.open("today")
      pcall(fake_dam.settle, function()
        return #fake_dam.argv_log(fake) > before
      end, 1000)

      assert(#fake_dam.argv_log(fake) > before, "a locked store must not refuse the name for the session")
    end, {
      name = "today",
      exit = 1,
      stderr = '{"error": {"kind": "store", "rule": null, "message": "the store is locked", "oids": []}}',
    })
  end,

  ["draws dam's own wording in the buffer when it refused the view"] = function()
    list_buffer.with(function(buf)
      local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")

      assert(body:find("dam refused this view:", 1, true), body)
      assert(body:find("unexpected nonsense in query", 1, true), body)
    end, {
      name = "nonsense",
      exit = 1,
      stderr = '{"error": {"kind": "parse", "rule": null, "message": "unexpected nonsense in query", "oids": []}}',
    })
  end,

  ["R re-reads the view, and za folds a subtree away"] = function()
    list_buffer.with(function(buf, fake)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("R", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)
      assert(fake_dam.argv_log(fake)[before + 1] == "ls --json", vim.inspect(fake_dam.argv_log(fake)))

      fake_dam.settle(function()
        return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("- child", 1, true) ~= nil
      end)
      local full = vim.api.nvim_buf_line_count(buf)
      list_buffer.cursor_to(buf, "- parent")
      vim.api.nvim_feedkeys("za", "x", false)

      -- A fold here means lines that were never drawn, not lines hidden.
      assert(vim.api.nvim_buf_line_count(buf) < full, "the child's line is gone")
      assert(
        not table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("- child", 1, true),
        "the child is still drawn"
      )
    end)
  end,

  ["<CR> opens the object on the line as a task buffer"] = function()
    list_buffer.with(function(buf, fake)
      list_buffer.cursor_to(buf, "buy oat milk")
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(
        fake_dam.argv_log(fake)[before + 1] == "show c30414962aa4332b6e5dfc2e0360e2b328735efe --json",
        vim.inspect(fake_dam.argv_log(fake))
      )
    end)
  end,

  ["<CR> on the title says there is no object there and opens nothing"] = function()
    list_buffer.with(function(_, fake, notifications)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)

      assert(#fake_dam.argv_log(fake) == before, vim.inspect(fake_dam.argv_log(fake)))
      assert(notifications[#notifications] == "damnit.nvim: no object on this line", vim.inspect(notifications))
    end)
  end,
}
