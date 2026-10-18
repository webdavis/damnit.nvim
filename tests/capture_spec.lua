local app = require("damnit").app()
local TESTS_DIR = require("helpers.paths").TESTS

local fake_process = require("helpers.fake_process")
local capture = require("damnit.capture")
local function queue()
  return require("damnit").app().queue
end

local PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP = TESTS_DIR .. "/../plugin/damnit.lua"
dofile(PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP)

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
    local fake = fake_process.install({ fixtures = TESTS_DIR .. "/fixtures/full" })

    local said = fake.said

    capture.create(app, "", nil)
    fake_process.drain()

    local log = fake_process.argv_log(fake)

    fake_process.remove(fake)

    assert(#log == 0, vim.inspect(log))
    assert(said[#said] == "damnit.nvim: there is nothing to capture here", vim.inspect(said))
  end,

  [":Dam capture over a range sends that argv and says what it captured"] = function()
    local fake = fake_process.install({ fixtures = TESTS_DIR .. "/fixtures/full" })

    local said = fake.said

    local prompts_opened = 0
    local real_input = vim.ui.input
    vim.ui.input = function()
      prompts_opened = prompts_opened + 1
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "-- TODO: hold the sidebar width" })
    vim.api.nvim_win_set_buf(0, buf)

    vim.cmd("1,1Dam capture")
    fake_process.settle(function()
      return queue().running() == nil and #said > 0
    end)

    vim.ui.input = real_input
    local log = fake_process.argv_log(fake)

    vim.cmd("silent! %bwipeout!")
    fake_process.remove(fake)

    assert(prompts_opened == 0, "a range makes the selection the subject, so nothing should have been asked for")
    assert(
      log[#log] == "new hold the sidebar width --path inbox/ --json",
      "a scratch buffer is no file with a line in it, so no location and no --body: " .. vim.inspect(log)
    )
    assert(said[#said] == "damnit.nvim: captured hold the sidebar width", vim.inspect(said))
  end,
}
