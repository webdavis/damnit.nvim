local with_dam = require("helpers.harness").with_dam
local harness = require("helpers.harness")
local app = require("damnit").app()
local fake_process = require("helpers.fake_process")
local status_window = require("helpers.status_window")
local render = require("damnit.render")
local window = require("damnit.window")

local function tick_twice_by_hand_full_redraw_then_header_only()
  window.tick(app, app.store)
  window.tick(app, app.store)
end

return {
  ["says how long ago each remote pulled, against the real clock"] = function()
    with_dam(status_window.opts(), function()
      local remotes = vim.api.nvim_buf_get_lines(window.buffer(app), 1, 2, false)[1]

      assert(remotes:find("fake %(1 unpushed, pulled %d+d ago%)"), remotes)
      assert(remotes:find("flaky (7 unpushed, never pulled)", 1, true), remotes)
    end)
  end,

  ["leaves the poller's own read out of the header"] = function()
    with_dam(status_window.opts(), function(dam)
      local buf = window.buffer(app)
      local before = #fake_process.argv_log(dam.fake)

      app.queue.submit({ args = { "ls", "--json" }, label = "ls", background = true })

      tick_twice_by_hand_full_redraw_then_header_only()

      local header = vim.api.nvim_buf_get_lines(buf, 0, 4, false)
      for _, line in ipairs(header) do
        assert(
          not line:find("Running:", 1, true),
          "an open window would flash the poller's label every minute: " .. vim.inspect(header)
        )
      end

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before and app.queue.running() == nil
      end)
    end)
  end,

  ["writes the running operation into the header on a tick"] = function()
    with_dam(status_window.opts(), function(dam)
      local buf = window.buffer(app)
      local before = #fake_process.argv_log(dam.fake)

      app.queue.submit({ args = { "status", "--json" }, label = "push fake" })
      tick_twice_by_hand_full_redraw_then_header_only()

      local header = vim.api.nvim_buf_get_lines(buf, 0, 4, false)
      assert(header[3]:find("Running: push fake", 1, true), vim.inspect(header))
      assert(header[3]:find("[C-c to cancel]", 1, true), header[3])

      for lnum = 0, 2 do
        local marks = vim.api.nvim_buf_get_extmarks(buf, render.NAMESPACE, { lnum, 0 }, { lnum, -1 }, {})
        assert(#marks > 0, ("the header-only rewrite replaced row %d and left it with no mark"):format(lnum))
      end

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before and app.queue.running() == nil
      end)
    end)
  end,

  ["shows a running call in the header after setup, without a tick by hand"] = function()
    with_dam(status_window.opts(), function(dam)
      require("damnit").setup({})
      local buf = window.buffer(app)
      local before = #fake_process.argv_log(dam.fake)
      dam.fake.hold = true

      app.queue.submit({ args = { "status", "--json" }, label = "push fake" })

      local function row_3()
        return vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1]
      end
      assert(
        vim.wait(2000, function()
          return row_3():find("Running: push fake", 1, true) ~= nil
        end, 50),
        "setup cut the queue off from the header: " .. row_3()
      )

      dam.fake.release()
      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before and app.queue.running() == nil
      end)
    end)
  end,

  ["R reads the remote list and the status again, so a pull made elsewhere shows its age"] = function()
    with_dam(status_window.opts(), function(dam)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("R", "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) >= before + 2 and app.queue.running() == nil
      end)

      local log = fake_process.argv_log(dam.fake)
      assert(log[before + 1] == "remote list --json", vim.inspect(log))
      assert(log[before + 2] == "status --json", vim.inspect(log))
    end)
  end,

  ["asks for the remote list again when the first read failed"] = function()
    with_dam(status_window.opts({ fixtures = harness.fixtures("default") }), function(dam)
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("R", "x", false)

      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before
      end)

      assert(
        fake_process.argv_log(dam.fake)[before + 1] == "remote list --json",
        vim.inspect(fake_process.argv_log(dam.fake))
      )
    end)
  end,
}
