local M = {}

function M.once_loaded(name, run)
  return function(...)
    local module = package.loaded[name]
    if module then
      run(module, ...)
    end
  end
end

function M.setup(app)
  local group = vim.api.nvim_create_augroup("damnit", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "damstatus", "damlist" },
    desc = "dam: the keys of a dam window",
    callback = function(event)
      require("damnit.keys").attach(event.buf, event.match, app)
    end,
  })

  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = group,
    desc = "dam: the legend keeps whole entries when the status window narrows",
    callback = M.once_loaded("damnit.window", function(window)
      window.tick_every_store(app)
    end),
  })

  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = "damnit://status/*",
    desc = "dam: :e re-reads the status",
    callback = M.once_loaded("damnit.window", function(window)
      window.refresh(app)
    end),
  })

  vim.api.nvim_create_autocmd({ "WinNew", "WinResized" }, {
    group = group,
    desc = "dam: hold the sidebar at its configured width",
    callback = M.once_loaded("damnit.sidebar", function(sidebar)
      sidebar.hold_width(app)
    end),
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    desc = "dam: stop the refresh timer",
    callback = M.once_loaded("damnit.poll", function(poll)
      poll.stop()
    end),
  })
end

return M
