local M = {}

local function named(value)
  return type(value) == "string" and value ~= ""
end

function M.of(options)
  if named(options.store) then
    return options.store
  end

  if named(vim.env.DAM_STORE) then
    return vim.env.DAM_STORE
  end

  return "default"
end

function M.display(store)
  if store == "default" then
    return "dam's default"
  end

  return vim.fn.fnamemodify(store, ":~")
end

return M
