-- Getting back to the code a task came from.
--
-- A body is text a person can edit on their phone, so these cases are mostly
-- about what `jump` does with one it cannot use. Nothing here reaches a task
-- store: a location is a string, and the files are made by the spec.

local location_edit = require("damnit.location_edit")

--- A repository holding one file of `lines` lines.
---@param lines integer
---@return string root
---@return string relative path of the file inside it
local function repository(lines)
  local root = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(root .. "/lua", "p")

  local handle = assert(io.open(root .. "/.git", "w"))
  handle:write("gitdir: elsewhere\n")
  handle:close()

  handle = assert(io.open(root .. "/lua/thing.lua", "w"))
  for number = 1, lines do
    handle:write("line " .. number .. "\n")
  end
  handle:close()

  return root, "lua/thing.lua"
end

--- Jump from inside `root`, in a tabpage of its own, and report what was said.
---@param root string the directory the editor is in
---@param parsed damnit.Location?
---@return boolean jumped
---@return string[] said
---@return string opened the file the window ended on
---@return integer line the cursor's line
local function jump_from(root, parsed)
  local real_notify, cwd = vim.notify, vim.uv.cwd()
  local said = {}
  vim.notify = function(message)
    table.insert(said, message)
  end

  vim.cmd("tabnew")
  vim.cmd.tcd(vim.fn.fnameescape(root))

  local ok, jumped = pcall(location_edit.jump, parsed)

  local opened = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
  local line = vim.api.nvim_win_get_cursor(0)[1]

  vim.cmd("tabclose")
  vim.cmd.tcd(vim.fn.fnameescape(cwd))
  vim.notify = real_notify

  assert(ok, jumped)

  return jumped, said, opened, line
end

return {
  ["jumps to the file and the line"] = function()
    local root, path = repository(20)
    local jumped, said, opened, line = jump_from(root, { repo = vim.fs.basename(root), path = path, line = 12 })

    assert(jumped, vim.inspect(said))
    -- Compared by suffix: the temporary directory is reached through a symlink
    -- on macOS, and the buffer holds the resolved name.
    assert(vim.endswith(opened, "/" .. path), opened)
    assert(line == 12, tostring(line))
    assert(#said == 0, vim.inspect(said))
  end,

  ["refuses a task whose body holds no location"] = function()
    local root = repository(3)
    local jumped, said = jump_from(root, nil)

    assert(jumped == false, "a task with no location was jumped to")
    assert(#said == 1 and said[1]:find("no location in its body", 1, true), vim.inspect(said))
  end,

  ["refuses a location whose file is gone"] = function()
    local root = repository(3)
    local jumped, said = jump_from(root, { repo = vim.fs.basename(root), path = "lua/moved.lua", line = 1 })

    assert(jumped == false, "a missing file was jumped to")
    assert(#said == 1 and said[1]:find("there is no file at lua/moved.lua", 1, true), vim.inspect(said))
  end,

  ["refuses a location captured in another repository, and names both"] = function()
    local root = repository(3)
    local jumped, said = jump_from(root, { repo = "some-other-repo", path = "lua/thing.lua", line = 1 })

    assert(jumped == false, "a location from another repository was jumped to")
    assert(said[1]:find("some-other-repo", 1, true), vim.inspect(said))
    assert(said[1]:find(vim.fs.basename(root), 1, true), vim.inspect(said))
  end,

  ["says so when the line is past the end, and lands on the last one"] = function()
    local root, path = repository(4)
    local jumped, said, opened, line = jump_from(root, { repo = vim.fs.basename(root), path = path, line = 99 })

    assert(jumped, vim.inspect(said))
    -- Compared by suffix: the temporary directory is reached through a symlink
    -- on macOS, and the buffer holds the resolved name.
    assert(vim.endswith(opened, "/" .. path), opened)
    assert(line == 4, tostring(line))
    assert(#said == 1 and said[1]:find("has 4 lines", 1, true), vim.inspect(said))
  end,
}
