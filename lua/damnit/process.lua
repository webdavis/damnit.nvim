local M = {}

function M.timeout_seconds(options)
  return math.max(tonumber(options.timeout) or 120, 1)
end

local function answer_on_the_main_loop(on_exit)
  return function(out)
    vim.schedule(function()
      on_exit(out)
    end)
  end
end

function M.run(argv, seconds, on_exit)
  local binary_found, handle =
    pcall(vim.system, argv, { text = true, timeout = seconds * 1000 }, answer_on_the_main_loop(on_exit))

  if not binary_found then
    vim.schedule(function()
      on_exit({ code = -1, stdout = "", stderr = "", missing = true })
    end)

    return nil
  end

  return handle
end

return M
