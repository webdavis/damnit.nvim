-- Capturing a task from code: what the description carries, and what the
-- content becomes.
--
-- Nothing here reaches Todoist. `client.create_task` is replaced with a fake
-- that records the fields it was handed, so no token is needed and no request
-- is made.

local capture = require("damnit.capture")
local client = require("damnit.client")

--- A directory holding the files named, and a `.git` file when `git` is true,
--- which is what marks it a repository root.
---@param files table<string, string>
---@param git boolean
---@return string root
local function tree(files, git)
  local root = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(root, "p")

  if git then
    files[".git"] = "gitdir: elsewhere\n"
  end

  for path, contents in pairs(files) do
    local full = root .. "/" .. path
    vim.fn.mkdir(vim.fs.dirname(full), "p")

    local handle = assert(io.open(full, "w"))
    handle:write(contents)
    handle:close()
  end

  return root
end

--- Run `body` with the create request faked and `vim.ui.input` answering with
--- `answer`, and report every task it tried to make.
---@param answer string|false|nil what the prompt is answered with, false for a cancel
---@param body fun()
---@return table[] created the fields of each task
---@return string[] prompts the default each prompt started on
local function capturing(answer, body)
  local real_create, real_input, real_notify = client.create_task, vim.ui.input, vim.notify
  local created, prompts = {}, {}

  client.create_task = function(fields, callback)
    table.insert(created, fields)
    callback({ id = "6XGg" })
  end

  vim.ui.input = function(opts, callback)
    table.insert(prompts, opts.default)
    callback(answer ~= false and answer or nil)
  end

  vim.notify = function() end

  local ok, err = pcall(body)

  client.create_task, vim.ui.input, vim.notify = real_create, real_input, real_notify
  assert(ok, err)

  return created, prompts
end

--- Open a file in a fresh window and capture the lines given, or the cursor's
--- line when none are.
---@param path string
---@param range { line1: integer, line2: integer }?
---@param answer string|false|nil
---@return table[] created
---@return string[] prompts
local function capture_in(path, range, answer)
  return capturing(answer, function()
    vim.cmd("tabnew")
    vim.cmd.edit(vim.fn.fnameescape(path))
    vim.api.nvim_win_set_cursor(0, { range and range.line1 or 1, 0 })

    capture.capture(range)

    vim.cmd("tabclose")
  end)
end

local CODE = table.concat({
  "local M = {}",
  "-- TODO: hold the width the way nvim-tree does",
  "/*",
  " * FIXME(stephen): the second line",
  " * and the third one too",
  " */",
  "return M",
}, "\n")

return {
  ["a capture inside a repository carries the repository and a relative path"] = function()
    local root = tree({ ["lua/thing.lua"] = CODE }, true)
    local created = capture_in(root .. "/lua/thing.lua", { line1 = 2, line2 = 2 })

    assert(#created == 1, vim.inspect(created))
    assert(created[1].description == vim.fs.basename(root) .. " lua/thing.lua:2", created[1].description)
  end,

  ["a capture outside a repository carries the file name alone, never a path from the machine"] = function()
    local root = tree({ ["thing.lua"] = CODE }, false)
    local created = capture_in(root .. "/thing.lua", { line1 = 2, line2 = 2 })

    assert(#created == 1, vim.inspect(created))
    assert(created[1].description == "thing.lua:2", created[1].description)
    assert(not created[1].description:find(root, 1, true), created[1].description)
    assert(not created[1].description:find(vim.fs.normalize(vim.env.HOME), 1, true), created[1].description)
  end,

  ["a capture from a buffer with no file makes a task with no description"] = function()
    local created = capturing("write the thing down", function()
      vim.cmd("tabnew")
      capture.capture(nil)
      vim.cmd("tabclose")
    end)

    assert(#created == 1, vim.inspect(created))
    assert(created[1].content == "write the thing down", vim.inspect(created[1]))
    assert(created[1].description == nil, vim.inspect(created[1]))
  end,

  ["one selected line becomes the content, without its comment leader or marker"] = function()
    local root = tree({ ["lua/thing.lua"] = CODE }, true)
    local created = capture_in(root .. "/lua/thing.lua", { line1 = 2, line2 = 2 })

    assert(created[1].content == "hold the width the way nvim-tree does", created[1].content)
  end,

  ["several selected lines become one line, and only the first loses its marker"] = function()
    local root = tree({ ["lua/thing.lua"] = CODE }, true)
    local created = capture_in(root .. "/lua/thing.lua", { line1 = 3, line2 = 6 })

    assert(created[1].content == "the second line and the third one too", created[1].content)
  end,

  ["a selection with no comment marker is taken as it stands"] = function()
    local root = tree({ ["lua/thing.lua"] = CODE }, true)
    local created = capture_in(root .. "/lua/thing.lua", { line1 = 1, line2 = 1 })

    assert(created[1].content == "local M = {}", created[1].content)
  end,

  ["with no selection the prompt starts on the cursor's line, and the answer is the content"] = function()
    local root = tree({ ["lua/thing.lua"] = CODE }, true)
    local created, prompts = capturing("hold the width", function()
      vim.cmd("tabnew")
      vim.cmd.edit(vim.fn.fnameescape(root .. "/lua/thing.lua"))
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      capture.capture(nil)

      vim.cmd("tabclose")
    end)

    assert(prompts[1] == "hold the width the way nvim-tree does", vim.inspect(prompts))
    assert(created[1].content == "hold the width", vim.inspect(created))
    assert(created[1].description == vim.fs.basename(root) .. " lua/thing.lua:2", created[1].description)
  end,

  ["a cancelled prompt makes no task"] = function()
    local root = tree({ ["lua/thing.lua"] = CODE }, true)
    local created = capture_in(root .. "/lua/thing.lua", nil, false)

    assert(#created == 0, vim.inspect(created))
  end,
}
