local tests_dir = arg[0]:match("(.*)/") or "."
local project_root = tests_dir .. "/.."
local only = arg[1]

package.path = ("%s/lua/?.lua;%s/lua/?/init.lua;%s"):format(project_root, project_root, package.path)

local function spec_files_to_run()
  if only then
    return { ("%s/%s.lua"):format(tests_dir, only) }
  end

  return vim.fn.glob(tests_dir .. "/*_spec.lua", false, true)
end

local function refuse_a_run_that_would_pass_by_testing_nothing(spec_files)
  if #spec_files == 0 then
    error("no spec files matched under " .. tests_dir)
  end
end

local function cases_refusing_a_gutted_spec_that_would_pass_silently(path, spec)
  local cases = dofile(path)

  if type(cases) ~= "table" or next(cases) == nil then
    error(spec .. " returned no cases")
  end

  return cases
end

local function names_in_the_same_order_every_run(cases)
  local names = {}
  for name in pairs(cases) do
    table.insert(names, name)
  end
  table.sort(names)

  return names
end

local function report_through_stdout_not_print(line)
  io.write(line, "\n")
end

local spec_files = spec_files_to_run()
refuse_a_run_that_would_pass_by_testing_nothing(spec_files)

local failures = 0
local passes = 0
local started_at = vim.uv.hrtime()

for _, path in ipairs(spec_files) do
  local spec = path:match("([^/]+)%.lua$")
  local cases = cases_refusing_a_gutted_spec_that_would_pass_silently(path, spec)

  for _, name in ipairs(names_in_the_same_order_every_run(cases)) do
    local ok, err = pcall(cases[name])
    if ok then
      passes = passes + 1
      report_through_stdout_not_print(("ok %s: %s"):format(spec, name))
    else
      failures = failures + 1
      report_through_stdout_not_print(("FAIL %s: %s: %s"):format(spec, name, err))
    end
  end
end

report_through_stdout_not_print(
  ("%d passed, %d failed in %.2fs"):format(passes, failures, (vim.uv.hrtime() - started_at) / 1e9)
)

os.exit(failures == 0 and 0 or 1)
