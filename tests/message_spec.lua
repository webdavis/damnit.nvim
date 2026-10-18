local message = require("damnit.message")

local function notifications(run)
  local seen = {}
  local real = vim.notify
  vim.notify = function(text, level)
    table.insert(seen, { text = text, level = level })
  end

  local ok, err = pcall(run)

  vim.notify = real
  assert(ok, err)

  return seen
end

local function history()
  return vim.api.nvim_exec2("messages", { output = true }).output
end

local DAM_REFUSAL_OF_254_COLUMNS = ('--due: cannot read "whenever-ish" as a date; '):rep(5)
  .. "try 2026-09-25, today or now."

return {
  ["prefixes what the plugin itself says"] = function()
    local seen = notifications(function()
      message.warn("nothing is staged")
    end)

    assert(#seen == 1, vim.inspect(seen))
    assert(seen[1].text == "damnit.nvim: nothing is staged", seen[1].text)
    assert(seen[1].level == vim.log.levels.WARN, tostring(seen[1].level))
  end,

  ["prefixes dam's own wording too, as a warning"] = function()
    local seen = notifications(function()
      message.report({ kind = "refused", code = 4, message = "78b8950 cannot be completed" })
    end)

    assert(seen[1].text == "damnit.nvim: 78b8950 cannot be completed", seen[1].text)
    assert(seen[1].level == vim.log.levels.WARN, tostring(seen[1].level))
  end,

  ["a missing dam is an error"] = function()
    local seen = notifications(function()
      message.report({ kind = "missing", code = -1, message = "dam was not found on PATH", plugin = true })
    end)

    assert(seen[1].text == "damnit.nvim: dam was not found on PATH", seen[1].text)
    assert(seen[1].level == vim.log.levels.ERROR, tostring(seen[1].level))
  end,

  ["cuts a long refusal to the command line at 80 columns and keeps the whole of it in :messages"] = function()
    vim.o.columns = 80
    assert(#DAM_REFUSAL_OF_254_COLUMNS == 254, tostring(#DAM_REFUSAL_OF_254_COLUMNS))

    local seen = notifications(function()
      message.report({ kind = "usage", code = 2, message = DAM_REFUSAL_OF_254_COLUMNS })
    end)

    assert(#seen == 1, vim.inspect(seen))
    assert(vim.startswith(seen[1].text, "damnit.nvim: --due: cannot read"), seen[1].text)
    assert(vim.endswith(seen[1].text, "…"), seen[1].text)
    assert(vim.fn.strdisplaywidth(seen[1].text) <= 68, tostring(vim.fn.strdisplaywidth(seen[1].text)))
    assert(history():find("damnit.nvim: " .. DAM_REFUSAL_OF_254_COLUMNS, 1, true), history():sub(-300))
  end,

  ["shows only the first line of a message that has several"] = function()
    local seen = notifications(function()
      message.say("3 sent\n1 failed: rate limited")
    end)

    assert(seen[1].text == "damnit.nvim: 3 sent", seen[1].text)
  end,
}
