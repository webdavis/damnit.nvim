local M = {}

local scratch = require("damnit.scratch")

M.PREFIX = "damnit.nvim: "
M.NAME = "damnit://messages"
M.KEEP = 200

local ELLIPSIS = "…"

local function first_line(text)
  return (text:gsub("\n.*", ""))
end

local function cut_to(line, room)
  local cut = line
  while vim.fn.strdisplaywidth(cut .. ELLIPSIS) > room do
    cut = vim.fn.strcharpart(cut, 0, vim.fn.strchars(cut) - 1)
  end

  return cut .. ELLIPSIS
end

local function lines_of(kept)
  local lines = {}
  for _, whole in ipairs(kept) do
    vim.list_extend(lines, vim.split(whole, "\n", { plain = true }))
  end

  return lines
end

function M.new(notify)
  local say = {}
  local kept = {}

  local function keep(whole)
    kept[#kept + 1] = whole

    if #kept > M.KEEP then
      table.remove(kept, 1)
    end
  end

  function say.kept()
    return vim.list_slice(kept)
  end

  function say.tell(level, text)
    local whole = M.PREFIX .. text
    local line = first_line(whole)
    local too_wide = vim.fn.strdisplaywidth(line) > vim.v.echospace

    keep(whole)
    notify(too_wide and cut_to(line, vim.v.echospace) or line, level)
  end

  function say.info(text)
    say.tell(vim.log.levels.INFO, text)
  end

  function say.warn(text)
    say.tell(vim.log.levels.WARN, text)
  end

  function say.fail(text)
    say.tell(vim.log.levels.ERROR, text)
  end

  ---@param err damnit.Failure
  function say.report(err)
    say.tell(err.kind == "missing" and vim.log.levels.ERROR or vim.log.levels.WARN, err.message)
  end

  function say.show()
    local lines = lines_of(kept)

    scratch.read_only(M.NAME, lines, "split")
    vim.api.nvim_win_set_cursor(0, { math.max(#lines, 1), 0 })
  end

  return say
end

return M
