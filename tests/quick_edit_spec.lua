-- The quick edits, by the argv each one sends.

local TESTS_DIR = arg[0]:match("(.*)/") or "."

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local list_buffer = dofile(TESTS_DIR .. "/helpers/list_buffer.lua")
local quick_edit = require("damnit.quick_edit")

local MILK = "c30414962aa4332b6e5dfc2e0360e2b328735efe"
local CHILD = "8fbff8b04f0bdbd5eb5d9a1ee81c82ace01e65b1"

--- Press a key on the object whose line holds `needle` and hand back the argv
--- lines that went out because of it.
---@param key string
---@param answer string? what vim.ui.input or vim.ui.select answers with
---@param needle string?
---@param count integer? how many calls to wait for
---@return string[]
local function sent(key, answer, needle, count)
  local new = {}

  list_buffer.with(function(buf, fake)
    list_buffer.cursor_to(buf, needle or "buy oat milk")
    local before = #fake_dam.argv_log(fake)

    local input, select = vim.ui.input, vim.ui.select
    vim.ui.input = function(_, on_answer)
      on_answer(answer)
    end
    vim.ui.select = function(items, _, on_choice)
      for index, item in ipairs(items) do
        local named = type(item) == "table" and item.name or tostring(item)

        if named == answer then
          return on_choice(item, index)
        end
      end

      on_choice(items[1], 1)
    end

    vim.api.nvim_feedkeys(key, "x", false)
    -- A case expecting no call still waits long enough for one to be logged,
    -- so an accidental call is caught rather than raced past.
    pcall(fake_dam.settle, function()
      return #fake_dam.argv_log(fake) >= before + math.max(count or 1, 1)
    end, (count == 0) and 200 or 1000)

    vim.ui.input, vim.ui.select = input, select
    new = vim.list_slice(fake_dam.argv_log(fake), before + 1)
  end)

  return new
end

return {
  ["dd removes the object after a confirm"] = function()
    local new = sent("dd", "y")

    assert(new[1] == ("rm %s --json"):format(MILK), vim.inspect(new))
  end,

  ["dd on any other answer sends nothing"] = function()
    local new = sent("dd", "n", nil, 0)

    assert(#new == 0, vim.inspect(new))
  end,

  ["p cycles the priority 4, 3, 2, 1, 4"] = function()
    assert(quick_edit.cycled(4) == 3, tostring(quick_edit.cycled(4)))
    assert(quick_edit.cycled(3) == 2)
    assert(quick_edit.cycled(2) == 1)
    assert(quick_edit.cycled(1) == 4)
    assert(quick_edit.cycled(nil) == 3, "an object with no priority is at dam's least urgent")

    local new = sent("p", nil)
    assert(new[1] == ("edit %s -p 4 --json"):format(MILK), vim.inspect(new))
  end,

  ["s sends the typed line unparsed, because dam parses a due string"] = function()
    local new = sent("s", "next tuesday at 9")

    assert(new[1] == ("edit %s --due next tuesday at 9 --json"):format(MILK), vim.inspect(new))
  end,

  ["l adds a label it does not have and removes one it does"] = function()
    local added = sent("l", "slow", nil, 2)
    assert(added[1] == "category list --json", vim.inspect(added))
    assert(added[2] == ("edit %s --label slow --json"):format(MILK), vim.inspect(added))

    local removed = sent("l", "home", nil, 2)
    assert(removed[2] == ("edit %s --unlabel home --json"):format(MILK), vim.inspect(removed))
  end,

  ["m moves the object into a path chosen from the paths in view"] = function()
    local new = sent("m", "work/parent/")

    assert(new[1] == ("mv %s work/parent/ --json"):format(MILK), vim.inspect(new))
  end,

  ["m offers a container path that no object in the view sits at"] = function()
    -- The fixture holds work/parent/ and work/parent/child/ and nothing at
    -- work/, which `>` can still reach, so the picker has to offer it too.
    local new = sent("m", "work/")

    assert(new[1] == ("mv %s work/ --json"):format(MILK), vim.inspect(new))
  end,

  ["a creates one at the path the cursor is in"] = function()
    local new = sent("a", "buy stamps")

    assert(new[1] == "new buy stamps --path inbox/ --json", vim.inspect(new))
  end,

  ["> moves the object into the path of the row above it"] = function()
    local new = sent(">", nil)

    assert(new[1] == ("mv %s work/parent/child/ --json"):format(MILK), vim.inspect(new))
  end,

  ["< moves the object out into the path its parent sits in"] = function()
    local new = sent("<", nil, "- child")

    assert(new[1] == ("mv %s work/ --json"):format(CHILD), vim.inspect(new))
  end,

  ["< on a row this view draws at the top says why and moves nothing"] = function()
    local new = sent("<", nil, "- parent", 0)

    assert(#new == 0, vim.inspect(new))
  end,

  ["X reopens a completed object, which dam edit takes a flag for"] = function()
    local new = sent("X", nil)

    assert(new[1] == ("edit %s --undone --json"):format(MILK), vim.inspect(new))
  end,
}
