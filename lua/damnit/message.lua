local M = {}

M.PREFIX = "damnit.nvim: "

function M.say(text)
  vim.notify(M.PREFIX .. text, vim.log.levels.INFO)
end

function M.warn(text)
  vim.notify(M.PREFIX .. text, vim.log.levels.WARN)
end

function M.fail(text)
  vim.notify(M.PREFIX .. text, vim.log.levels.ERROR)
end

function M.report(err)
  local level = err.kind == "missing" and vim.log.levels.ERROR or vim.log.levels.WARN

  if err.plugin then
    return vim.notify(M.PREFIX .. err.message, level)
  end

  vim.notify(err.message, level)
end

return M
