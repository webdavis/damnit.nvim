local damnit = require("damnit")
local said = require("helpers.said")

local function notifications(run)
  local say, lines, levels = said.recorder()
  local before = damnit.app().say
  damnit.setup({}, { say = say })

  local ok, err = pcall(run, say)

  damnit.setup({}, { say = before })
  assert(ok, err)

  local seen = {}
  for index, text in ipairs(lines) do
    seen[index] = { text = text, level = levels[index] }
  end

  return seen, say
end

local PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP = require("helpers.paths").TESTS .. "/../plugin/damnit.lua"
dofile(PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP)

local function shown_by_dam_messages()
  vim.cmd("Dam messages")
  local buf = vim.api.nvim_get_current_buf()

  assert(vim.api.nvim_buf_get_name(buf) == "damnit://messages", vim.api.nvim_buf_get_name(buf))
  assert(vim.bo[buf].modifiable == false, "the messages buffer is read only")

  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

local DAM_REFUSAL_OF_254_COLUMNS = ('--due: cannot read "whenever-ish" as a date; '):rep(5)
  .. "try 2026-09-25, today or now."

return {
  ["prefixes what the plugin itself says"] = function()
    local seen = notifications(function(say)
      say.warn("nothing is staged")
    end)

    assert(#seen == 1, vim.inspect(seen))
    assert(seen[1].text == "damnit.nvim: nothing is staged", seen[1].text)
    assert(seen[1].level == vim.log.levels.WARN, tostring(seen[1].level))
  end,

  ["prefixes dam's own wording too, as a warning"] = function()
    local seen = notifications(function(say)
      say.report({ kind = "refused", code = 4, message = "78b8950 cannot be completed" })
    end)

    assert(seen[1].text == "damnit.nvim: 78b8950 cannot be completed", seen[1].text)
    assert(seen[1].level == vim.log.levels.WARN, tostring(seen[1].level))
  end,

  ["a missing dam is an error"] = function()
    local seen = notifications(function(say)
      say.report({ kind = "missing", code = -1, message = "dam was not found on PATH", plugin = true })
    end)

    assert(seen[1].text == "damnit.nvim: dam was not found on PATH", seen[1].text)
    assert(seen[1].level == vim.log.levels.ERROR, tostring(seen[1].level))
  end,

  ["cuts a long refusal to the command line at 80 columns and keeps the whole of it for :Dam messages"] = function()
    vim.o.columns = 80
    assert(#DAM_REFUSAL_OF_254_COLUMNS == 254, tostring(#DAM_REFUSAL_OF_254_COLUMNS))

    local shown
    local seen, say = notifications(function(say)
      say.report({ kind = "usage", code = 2, message = DAM_REFUSAL_OF_254_COLUMNS })
      shown = shown_by_dam_messages()
    end)

    assert(#seen == 1, vim.inspect(seen))
    assert(vim.startswith(seen[1].text, "damnit.nvim: --due: cannot read"), seen[1].text)
    assert(vim.endswith(seen[1].text, "…"), seen[1].text)
    assert(vim.fn.strdisplaywidth(seen[1].text) <= 68, tostring(vim.fn.strdisplaywidth(seen[1].text)))

    local kept = say.kept()
    assert(kept[#kept] == "damnit.nvim: " .. DAM_REFUSAL_OF_254_COLUMNS, vim.inspect(kept))
    assert(shown:find("damnit.nvim: " .. DAM_REFUSAL_OF_254_COLUMNS, 1, true), shown)
  end,

  ["a line that fits ends without an ellipsis"] = function()
    local seen = notifications(function(say)
      say.info("nothing to pull")
    end)

    assert(seen[1].text == "damnit.nvim: nothing to pull", seen[1].text)
  end,

  ["shows only the first line of a message that has several and keeps every line for :Dam messages"] = function()
    local shown
    local seen, say = notifications(function(say)
      say.info("3 sent\n1 failed: rate limited")
      shown = shown_by_dam_messages()
    end)

    assert(seen[1].text == "damnit.nvim: 3 sent", seen[1].text)

    local kept = say.kept()
    assert(kept[#kept] == "damnit.nvim: 3 sent\n1 failed: rate limited", vim.inspect(kept))
    assert(shown:find("damnit.nvim: 3 sent\n1 failed: rate limited", 1, true), shown)
  end,

  ["keeps the newest 200 messages, newest last"] = function()
    local _, say = notifications(function(say)
      for i = 1, 205 do
        say.info(("note %d"):format(i))
      end
    end)

    local kept = say.kept()
    assert(#kept == 200, tostring(#kept))
    assert(kept[1] == "damnit.nvim: note 6", kept[1])
    assert(kept[200] == "damnit.nvim: note 205", kept[200])
  end,
}
