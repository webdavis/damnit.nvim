if vim.g.loaded_damnit then
  return
end
vim.g.loaded_damnit = true

local SUBCOMMANDS_TAKING_A_VIEW = { list = true, pick = true }

local SUBCOMMANDS = {
  [""] = function(app)
    require("damnit.window").open(app)
  end,
  cancel = function(app)
    app.queue.cancel()
  end,
  capture = function(app, _, cmd)
    local selection = cmd.range > 0 and { line1 = cmd.line1, line2 = cmd.line2 } or nil

    require("damnit.capture").capture(app, selection)
  end,
  done = function(app)
    require("damnit.list").open(app, require("damnit.views").COMPLETED)
  end,
  list = function(app, args)
    require("damnit.views").resolve_then(app, args[1], function(spec)
      require("damnit.list").open(app, spec)
    end)
  end,
  pick = function(app, args)
    require("damnit.picker").pick(app, args[1])
  end,
  messages = function(app)
    app.say.show()
  end,
  toggle = function(app)
    require("damnit.sidebar").toggle(app)
  end,
  task = function(app, args)
    if #args ~= 1 then
      return app.say.fail("usage is :Dam task <oid>")
    end

    require("damnit.task_buffer").open(app, args[1])
  end,
}

local function usage()
  local names = {}
  for name in pairs(SUBCOMMANDS) do
    if name ~= "" then
      names[#names + 1] = ":Dam " .. name
    end
  end
  table.sort(names)

  return "usage is :Dam, " .. table.concat(names, ", ")
end

local function complete(arg_lead, cmd_line)
  local typed = vim.split(vim.trim(cmd_line), "%s+")

  if #typed > 1 and SUBCOMMANDS_TAKING_A_VIEW[typed[2]] then
    local app = require("damnit").app()
    local views = require("damnit.views")
    local the_next_tab_offers_dams_filters_too = views.load
    the_next_tab_offers_dams_filters_too(app)

    return vim.tbl_filter(function(name)
      return vim.startswith(name, arg_lead)
    end, views.known(app))
  end

  local names = {}
  for name in pairs(SUBCOMMANDS) do
    if name ~= "" and vim.startswith(name, arg_lead) then
      names[#names + 1] = name
    end
  end
  table.sort(names)

  return names
end

vim.api.nvim_create_user_command("Dam", function(cmd)
  local app = require("damnit").app()
  local args = cmd.fargs
  local run = SUBCOMMANDS[args[1] or ""]

  if not run then
    return app.say.fail(usage())
  end

  run(app, vim.list_slice(args, 2), cmd)
end, {
  nargs = "*",
  range = true,
  complete = complete,
  desc = "dam: the staging window, a list, a task, a search, the history, the sidebar or a capture",
})
