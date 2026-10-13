local M = {}

local TESTS_DIR = arg[0]:match("(.*)/") or "."

M.COLUMNS = 80
M.LINES = 24

local function row_without_trailing_blanks(row)
  local cells = {}
  for column = 1, M.COLUMNS do
    cells[column] = vim.fn.screenstring(row, column)
  end

  return (table.concat(cells):gsub("%s+$", ""))
end

local function lay_the_windows_out_again_since_nvim_l_resizes_only_the_grid()
  vim.cmd("wincmd =")
end

function M.fix_size()
  if vim.o.columns == M.COLUMNS and vim.o.lines == M.LINES then
    return
  end

  vim.o.columns = M.COLUMNS
  vim.o.lines = M.LINES
  lay_the_windows_out_again_since_nvim_l_resizes_only_the_grid()
end

function M.dump()
  M.fix_size()
  vim.cmd("redraw!")

  local rows = {}
  for row = 1, M.LINES do
    rows[row] = row_without_trailing_blanks(row)
  end

  return table.concat(rows, "\n") .. "\n"
end

local function golden_path(name)
  return ("%s/golden/screen/%s.txt"):format(TESTS_DIR, name)
end

local function read(path)
  local file = assert(io.open(path, "r"), "no golden at " .. path .. "; regenerate with DAMNIT_GOLDEN_UPDATE=1")
  local text = file:read("*a")
  file:close()

  return text
end

local function write(path, text)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local file = assert(io.open(path, "w"))
  file:write(text)
  file:close()
end

function M.matches_golden(name)
  local got = M.dump()
  local path = golden_path(name)

  if vim.env.DAMNIT_GOLDEN_UPDATE == "1" then
    return write(path, got)
  end

  local want = read(path)
  assert(
    got == want,
    ("screen %s differs; regenerate with DAMNIT_GOLDEN_UPDATE=1 and read the diff before committing it\n"):format(name)
      .. ("--- got ---\n%s--- want ---\n%s"):format(got, want)
  )
end

return M
