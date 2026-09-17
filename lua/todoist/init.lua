-- todoist.nvim: Todoist from inside Neovim.
--
-- This module is options and nothing else. The two things worth knowing about
-- them are that a token is never one of them, and that they are read when a
-- request is made rather than copied into the client, so a `setup` call later
-- in a session changes the next request.

local M = {}

--- Every option at its default.
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
M.options = {
  token_command = nil,
  token_env = nil,
  base_url = "https://api.todoist.com/api/v1",
  curl = "curl",
  timeout = 15,
}

---@param opts todoist.Options?
function M.setup(opts)
  M.options = vim.tbl_extend("force", M.options, opts or {})

  -- A token already resolved under the old options is not the one the new
  -- options name.
  require("todoist.token").forget()
end

return M
