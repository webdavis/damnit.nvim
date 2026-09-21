-- The prefix rule: what this plugin says carries its name, what dam said does
-- not, so the two are never confused in a notification.

local message = require("damnit.message")

---@param run fun()
---@return { text: string, level: integer }[]
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

return {
  ["prefixes what the plugin itself says"] = function()
    local seen = notifications(function()
      message.warn("nothing is staged")
    end)

    assert(#seen == 1, vim.inspect(seen))
    assert(seen[1].text == "damnit.nvim: nothing is staged", seen[1].text)
    assert(seen[1].level == vim.log.levels.WARN, tostring(seen[1].level))
  end,

  ["carries dam's own wording unprefixed"] = function()
    local seen = notifications(function()
      message.report({ kind = "refused", code = 4, message = "78b8950 cannot be completed" })
    end)

    assert(seen[1].text == "78b8950 cannot be completed", seen[1].text)
    assert(seen[1].level == vim.log.levels.WARN, tostring(seen[1].level))
  end,

  ["prefixes an error the plugin wrote about dam rather than one dam wrote"] = function()
    local seen = notifications(function()
      message.report({ kind = "missing", code = -1, message = "dam was not found on PATH", plugin = true })
    end)

    assert(seen[1].text == "damnit.nvim: dam was not found on PATH", seen[1].text)
    assert(seen[1].level == vim.log.levels.ERROR, tostring(seen[1].level))
  end,
}
