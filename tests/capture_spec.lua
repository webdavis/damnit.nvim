-- A task made out of the code in front of you.
--
-- The argv is the contract, so most of these cases are the argv one capture
-- becomes. The last one drives `:Dam capture` over a range, which is what
-- proves the command, the range read and the call are wired to each other.

local TESTS_DIR = arg[0]:match("(.*)/") or "."

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local capture = require("damnit.capture")
local queue = require("damnit.queue")

-- `:Dam` is declared by the plugin file rather than by `setup`, so a spec that
-- runs the command loads it the way Neovim would.
dofile(TESTS_DIR .. "/../plugin/damnit.lua")

return {
  ["builds the argv dam new takes, with the location in the body"] = function()
    local args = capture.args("buy oat milk", { repo = "damnit.nvim", path = "lua/damnit/status.lua", line = 112 })

    assert(
      vim.deep_equal(args, {
        "new",
        "buy oat milk",
        "--path",
        "inbox/",
        "--body",
        "damnit.nvim lua/damnit/status.lua:112",
        "--json",
      }),
      vim.inspect(args)
    )
  end,

  ["leaves the body out when the buffer has no location"] = function()
    local args = capture.args("buy oat milk", nil)

    assert(vim.deep_equal(args, { "new", "buy oat milk", "--path", "inbox/", "--json" }), vim.inspect(args))
  end,

  ["joins a visual selection into one subject"] = function()
    assert(capture.content({ "  buy", "  oat milk  " }) == "buy oat milk", capture.content({ "  buy", "  oat milk  " }))
  end,

  ["drops the comment leader and the marker off the code it captured"] = function()
    local lines = { "  -- TODO: hold the sidebar", "  -- width the way nvim-tree does" }

    assert(capture.content(lines) == "hold the sidebar width the way nvim-tree does", capture.content(lines))
  end,

  ["captures nothing from lines holding no words"] = function()
    assert(capture.content({ "  ", "--" }) == "", capture.content({ "  ", "--" }))
  end,

  ["an empty subject is refused rather than sent"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
    queue.reset()

    local said = {}
    local real = vim.notify
    vim.notify = function(text)
      table.insert(said, text)
    end

    capture.create("", nil)
    -- Long enough for a call to reach the log, so one that should not have been
    -- made is caught rather than raced past.
    vim.wait(200, function()
      return #fake_dam.argv_log(fake) > 0
    end, 5)

    vim.notify = real
    local log = fake_dam.argv_log(fake)

    queue.reset()
    fake_dam.remove(fake)

    assert(#log == 0, vim.inspect(log))
    assert(said[#said] == "damnit.nvim: there is nothing to capture here", vim.inspect(said))
  end,

  [":Dam capture over a range sends that argv and says what it captured"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
    queue.reset()

    local said = {}
    local real = vim.notify
    vim.notify = function(text)
      table.insert(said, text)
    end

    -- A range means the selection is the subject, so nothing is asked for. The
    -- prompt is stubbed to record that rather than to answer: the real one has
    -- no terminal to read in a headless run.
    local asked = 0
    local real_input = vim.ui.input
    vim.ui.input = function()
      asked = asked + 1
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "-- TODO: hold the sidebar width" })
    vim.api.nvim_win_set_buf(0, buf)

    vim.cmd("1,1Dam capture")
    fake_dam.settle(function()
      return queue.running() == nil and #said > 0
    end)

    vim.notify = real
    vim.ui.input = real_input
    local log = fake_dam.argv_log(fake)

    vim.cmd("silent! %bwipeout!")
    queue.reset()
    fake_dam.remove(fake)

    -- A scratch buffer is no file with a line in it, so the capture carries no
    -- location and sends no `--body`.
    assert(asked == 0, "a range was given, so nothing should have been asked for")
    assert(log[#log] == "new hold the sidebar width --path inbox/ --json", vim.inspect(log))
    assert(said[#said] == "damnit.nvim: captured hold the sidebar width", vim.inspect(said))
  end,
}
