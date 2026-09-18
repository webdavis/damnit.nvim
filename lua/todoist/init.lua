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
---@field sidebar todoist.SidebarOptions how `toggle` puts a view beside your work
M.options = {
  token_command = nil,
  token_env = nil,
  base_url = "https://api.todoist.com/api/v1",
  curl = "curl",
  timeout = 15,
  views = {},
  sidebar = {
    side = "left",
    width = 40,
    view = "today",
  },
}

--- The sidebar's own options.
---
--- `view` names a view declared in `views`, which is why `today` is the default
--- here and not a filter: the word is the one the herdr pane uses for the same
--- list, and the filter behind it is yours to write.
---@class todoist.SidebarOptions
---@field side "left"|"right" the edge the split sits on
---@field width integer columns the split is held at
---@field view string the name of the view it opens

---@param opts todoist.Options?
function M.setup(opts)
  -- Deep, so naming one sidebar option keeps the defaults of the others.
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})

  -- A token already resolved under the old options is not the one the new
  -- options name.
  require("todoist.token").forget()
end

--- The list a view name means, or nil after saying there is no such view.
---
--- Resolving a name is separate from opening it because the sidebar needs the
--- answer before it changes the layout.
---@param name string? a view declared in `setup`, or nil for every open task
---@return todoist.ListSpec? spec
function M.view(name)
  if name == nil or name == "" then
    return { title = "all open tasks" }
  end

  local views = M.options.views or {}
  local filter = views[name]
  if type(filter) ~= "string" then
    local declared = vim.tbl_keys(views)
    table.sort(declared)

    local known = #declared > 0 and ("declared views are " .. table.concat(declared, ", "))
      or "no views are declared in setup"

    vim.notify(("todoist.nvim: there is no view named %q. %s"):format(name, known), vim.log.levels.ERROR)

    return nil
  end

  return { title = name, filter = filter }
end

--- Open a list of tasks: a named view, or every open task when called with no
--- name.
---
--- This is the function a keymap calls, and it is the one stable way in:
--- `vim.keymap.set("n", "<leader>tt", function() require("todoist").open("today") end)`.
---@param name string? a view declared in `setup`, or nil for every open task
---@return integer? buf the buffer the list is in, or nil when there is no such view
function M.open(name)
  local spec = M.view(name)
  if not spec then
    return nil
  end

  return require("todoist.list").open(spec)
end

--- Open the completed history, newest first.
---
--- The third function a keymap calls:
--- `vim.keymap.set("n", "<leader>td", require("todoist").completed)`.
---@return integer buf the buffer the history is in
function M.completed()
  return require("todoist.completed").open()
end

--- Open the sidebar, or close the one this tabpage already has.
---
--- The other function a keymap calls:
--- `vim.keymap.set("n", "<leader>tb", require("todoist").toggle)`.
function M.toggle()
  return require("todoist.sidebar").toggle()
end

return M
