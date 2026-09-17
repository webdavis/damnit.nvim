-- todoist.nvim: Todoist from inside Neovim.
--
-- This module is options and nothing else. The two things worth knowing about
-- them are that a token is never one of them, and that they are read when a
-- request is made rather than copied into the client, so a `setup` call later
-- in a session changes the next request.

local M = {}

--- Every option at its default.
---
--- `views` is empty, so the only list out of the box is every open task. A view
--- is a name and a Todoist filter query: `{ today = "today | overdue" }`. The
--- names are meant to match the herdr plugin's `[[views]]` entries, so the same
--- word opens the same list in the pane and in the editor.
---
--- `token_command` and `token_env` are both nil, which is not a working
--- configuration: one of them has to be set, because those are the only two
--- ways a token reaches this plugin. There is deliberately no third way and no
--- default path to read one from.
---@class todoist.Options
---@field token_command string[]? a command whose standard output is the token
---@field token_env string? the name of an environment variable holding the token
---@field base_url string the API root every request is built against
---@field curl string the curl executable, a bare name looked up on PATH or a path
---@field timeout integer seconds a request may take before curl gives up
---@field views table<string, string> a view name to the Todoist filter it runs
M.options = {
  token_command = nil,
  token_env = nil,
  base_url = "https://api.todoist.com/api/v1",
  curl = "curl",
  timeout = 15,
  views = {},
}

---@param opts todoist.Options?
function M.setup(opts)
  M.options = vim.tbl_extend("force", M.options, opts or {})

  -- A token already resolved under the old options is not the one the new
  -- options name.
  require("todoist.token").forget()
end

--- Open a list of tasks: a named view, or every open task when called with no
--- name.
---
--- This is the function a keymap calls, and it is the one stable way in:
--- `vim.keymap.set("n", "<leader>tt", function() require("todoist").open("today") end)`.
---@param name string? a view declared in `setup`, or nil for every open task
---@return integer? buf the buffer the list is in, or nil when there is no such view
function M.open(name)
  if name == nil or name == "" then
    return require("todoist.list").open({ title = "all open tasks" })
  end

  local views = M.options.views or {}
  local filter = views[name]
  if type(filter) ~= "string" then
    local declared = vim.tbl_keys(views)
    table.sort(declared)

    local known = #declared > 0 and ("declared views are " .. table.concat(declared, ", "))
      or "no views are declared in setup"

    return vim.notify(("todoist.nvim: there is no view named %q. %s"):format(name, known), vim.log.levels.ERROR)
  end

  return require("todoist.list").open({ title = name, filter = filter })
end

return M
