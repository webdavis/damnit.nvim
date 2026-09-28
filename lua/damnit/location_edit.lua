local message = require("damnit.message")

local M = {}

local function repository_root(path)
  local root = vim.fs.root(path, ".git")

  return root and vim.fs.normalize(root) or nil
end

local function names_a_file(buf, name)
  return name ~= "" and vim.bo[buf].buftype == "" and vim.fn.isdirectory(name) == 0
end

function M.of_buffer(buf, line)
  buf = buf or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1]

  local name = vim.api.nvim_buf_get_name(buf)
  if not names_a_file(buf, name) then
    return nil
  end

  local path = vim.fs.normalize(name)
  local root = repository_root(path)

  if root and vim.startswith(path, root .. "/") then
    return { repo = vim.fs.basename(root), path = path:sub(#root + 2), line = line }
  end

  return { path = vim.fs.basename(path), line = line }
end

local function refuse(text)
  message.warn(text)

  return false
end

function M.jump(location)
  if not location then
    return refuse("this task has no location in its body")
  end

  local cwd = vim.fs.normalize(vim.uv.cwd() or ".")
  local open_root = repository_root(cwd) or cwd
  local here = vim.fs.basename(open_root)

  if location.repo and location.repo ~= here then
    return refuse(("this task points into %s, and %s is what is open here"):format(location.repo, here))
  end

  local path = vim.fs.joinpath(open_root, location.path)
  if vim.fn.filereadable(path) == 0 then
    return refuse(("there is no file at %s"):format(location.path))
  end

  require("damnit.sidebar").leave_fixed_window()
  vim.cmd.edit(vim.fn.fnameescape(path))

  local last = vim.api.nvim_buf_line_count(0)
  local line = math.min(location.line, last)
  vim.api.nvim_win_set_cursor(0, { line, 0 })

  local file_shrank_under_the_task = line ~= location.line
  if file_shrank_under_the_task then
    message.warn(("%s has %d lines, so this is the last one"):format(location.path, last))
  end

  return true
end

return M
