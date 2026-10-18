local with_dam = require("helpers.harness").with_dam
local harness = require("helpers.harness")
local app = require("damnit").app()
local fake_process = require("helpers.fake_process")
local status_window = require("helpers.status_window")
local render = require("damnit.render")
local scratch = require("damnit.scratch")
local window = require("damnit.window")

local function tick_twice_by_hand_full_redraw_then_header_only()
  window.tick(app, app.store)
  window.tick(app, app.store)
end

return {
  ["opens one buffer per store and focuses it rather than opening a second"] = function()
    with_dam(status_window.opts(), function()
      local first = window.buffer(app)
      vim.cmd("wincmd p")
      local second = window.open(app)

      assert(first == second, "a second :Dam focuses the buffer the first opened")

      local shown = 0
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == first then
          shown = shown + 1
        end
      end
      assert(shown == 1, ("the buffer is in %d windows"):format(shown))
    end)
  end,

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

  ["- on the first of two Working entries leaves the cursor on the second"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.api.nvim_feedkeys("gu", "x", false)
      local line = vim.api.nvim_win_get_cursor(0)[1]
      dam.fake.fixtures = harness.fixtures("staged_first")
      local before = #fake_process.argv_log(dam.fake)

      vim.api.nvim_feedkeys("-", "x", false)
      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) >= before + 2 and app.queue.running() == nil
      end)

      local landed = vim.api.nvim_win_get_cursor(0)[1]
      assert(landed == line, ("the cursor left line %d for line %d"):format(line, landed))
      local found = window.entry_under_cursor(app)
      assert(found and found.section.kind == "working", vim.inspect(found and found.section.kind))
      assert(found.entry.oid:sub(1, 7) == "e648ce0", found.entry.oid)
    end)
  end,

  ["keeps a section the user folded closed when the re-read moves its heading"] = function()
    with_dam(status_window.opts(), function(dam)
      local buf = window.buffer(app)

      local function heading_of(kind)
        for index, row in ipairs(scratch.rows(buf)) do
          if row.kind == "section" and row.section == kind then
            return index
          end
        end

        error("no " .. kind .. " heading")
      end

      local heading = heading_of("staged")
      vim.api.nvim_win_set_cursor(0, { heading, 0 })
      vim.cmd("normal! zc")
      assert(vim.fn.foldclosed(heading) == heading, ("fold at %d: %d"):format(heading, vim.fn.foldclosed(heading)))

      local one_object_staged_so_the_staged_heading_slides_up = harness.fixtures("shifted")
      dam.fake.fixtures = one_object_staged_so_the_staged_heading_slides_up
      local before = #fake_process.argv_log(dam.fake)
      vim.api.nvim_feedkeys("R", "x", false)
      fake_process.settle(function()
        return #fake_process.argv_log(dam.fake) > before and app.queue.running() == nil
      end)

      local moved = heading_of("staged")
      assert(moved == heading - 1, ("heading %d did not move: %d"):format(heading, moved))
      assert(vim.fn.foldclosed(moved) == moved, "the re-read re-opened a section the user closed")
      assert(vim.fn.foldclosedend(moved) == moved + 2, tostring(vim.fn.foldclosedend(moved)))
    end)
  end,

  ["makes the buffer unmodifiable, unlisted and scratch"] = function()
    with_dam(status_window.opts(), function()
      local buf = window.buffer(app)

      assert(vim.bo[buf].filetype == "damstatus", vim.bo[buf].filetype)
      assert(vim.bo[buf].buftype == "nofile", vim.bo[buf].buftype)
      assert(vim.bo[buf].bufhidden == "hide", vim.bo[buf].bufhidden)
      assert(vim.bo[buf].modifiable == false)
      assert(vim.bo[buf].buflisted == false)
      assert(vim.bo[buf].swapfile == false)
    end)
  end,

  [":Dam says its usage, prefixed, for a word it does not know"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.cmd("Dam bogus")

      local said = dam.said[#dam.said]
      local one_member_of_a_list_that_grows_with_every_subcommand = ":Dam cancel"
      assert(vim.startswith(tostring(said), "damnit.nvim: usage is :Dam, "), tostring(said))
      assert(tostring(said):find(one_member_of_a_list_that_grows_with_every_subcommand, 1, true), tostring(said))
    end)
  end,

  ["says so rather than raising E444 when the window is the only one"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.cmd("only")
      local buf = window.buffer(app)
      vim.api.nvim_feedkeys("q", "x", false)

      assert(vim.api.nvim_win_get_buf(0) == buf, "the status window is still open")
      assert(
        dam.said[#dam.said] == "damnit.nvim: the status window is the only window open",
        tostring(dam.said[#dam.said])
      )
    end)
  end,

  ["reads the status from dam rather than guessing at it"] = function()
    with_dam(status_window.opts(), function(dam)
      local log = fake_process.argv_log(dam.fake)

      assert(vim.tbl_contains(log, "status --json"), vim.inspect(log))
      assert(vim.tbl_contains(log, "remote list --json"), vim.inspect(log))
      assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:find("Store:", 1, true), "the header is drawn")
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

  ["gu, gs and gc jump to a section, and a count picks the entry"] = function()
    with_dam(status_window.opts(), function()
      vim.api.nvim_feedkeys("gu", "x", false)
      local buf = vim.api.nvim_get_current_buf()
      local unstaged = vim.api.nvim_win_get_cursor(0)[1]
      assert(scratch.row(buf, unstaged).section == "working", "gu lands in Working")

      vim.api.nvim_feedkeys("2gu", "x", false)
      assert(vim.api.nvim_win_get_cursor(0)[1] == unstaged + 1, "a count picks the second entry")

      vim.api.nvim_feedkeys("gc", "x", false)
      local conflict = vim.api.nvim_win_get_cursor(0)[1]
      assert(scratch.row(buf, conflict).section == "conflicts", "gc lands in Conflicts")
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

  ["refuses a jump to a section this status has none of"] = function()
    with_dam(status_window.opts({ fixtures = harness.fixtures("default") }), function(dam)
      vim.api.nvim_feedkeys("gs", "x", false)

      assert(dam.said[#dam.said] == "damnit.nvim: no Staged section", dam.said[#dam.said])
    end)
  end,

  ["q hides the window and keeps the buffer"] = function()
    with_dam(status_window.opts(), function()
      local buf = window.buffer(app)
      vim.api.nvim_feedkeys("q", "x", false)

      assert(vim.api.nvim_buf_is_valid(buf), "the buffer survives, so a re-open is instant")
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        assert(vim.api.nvim_win_get_buf(win) ~= buf, "no window still shows it")
      end
    end)
  end,

  [":Dam cancel says nothing is running when nothing is"] = function()
    with_dam(status_window.opts(), function(dam)
      vim.cmd("Dam cancel")

      assert(dam.said[#dam.said] == "damnit.nvim: nothing is running", dam.said[#dam.said])
    end)
  end,
}
