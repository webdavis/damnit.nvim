local TESTS_DIR = arg[0]:match("(.*)/") or "."

local fake_process = dofile(TESTS_DIR .. "/helpers/fake_process.lua")
local damnit = require("damnit")

local SECOND_STORE = "/tmp/the-second-store.db"

local function buffer_text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

local function open_the_list()
  vim.cmd("Dam list")
  fake_process.drain()

  return vim.api.nvim_get_current_buf()
end

local function ls_calls(fake)
  return vim.tbl_filter(function(argv)
    return argv:find("ls !done", 1, true) ~= nil
  end, fake_process.argv_log(fake))
end

local function with_the_list_on(fixtures, run)
  dofile(TESTS_DIR .. "/../plugin/damnit.lua")
  local fake = fake_process.install({ fixtures = TESTS_DIR .. "/fixtures/" .. fixtures })

  local ok, err = pcall(run, fake)

  vim.cmd("silent! %bwipeout!")
  damnit.options.store = nil
  fake_process.remove(fake)

  assert(ok, err)
end

local function cursor_to(buf, needle)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:find(needle, 1, true) then
      return vim.api.nvim_win_set_cursor(0, { index, 0 })
    end
  end

  error("no line holds " .. needle)
end

return {
  ["a fold closed in one store's list is open in the next store's"] = function()
    with_the_list_on("full", function()
      local buf = open_the_list()
      cursor_to(buf, "- parent")
      vim.api.nvim_feedkeys("za", "x", false)
      assert(not buffer_text(buf):find("- child", 1, true), buffer_text(buf))

      damnit.setup({ store = SECOND_STORE })

      local second = buffer_text(open_the_list())
      assert(second:find("- child", 1, true), second)
    end)
  end,

  ["a list opened after setup names another store asks that store and draws its answer"] = function()
    with_the_list_on("full", function(fake)
      local first = buffer_text(open_the_list())
      assert(first:find("buy oat milk", 1, true), first)

      damnit.setup({ store = SECOND_STORE })
      fake.fixtures = TESTS_DIR .. "/fixtures/long"

      local second = buffer_text(open_the_list())
      local calls = ls_calls(fake)

      assert(calls[#calls] == "--store " .. SECOND_STORE .. " ls !done --json", vim.inspect(calls))
      assert(second:find("water the plants", 1, true), second)
      assert(not second:find("buy oat milk", 1, true), second)
    end)
  end,
}
