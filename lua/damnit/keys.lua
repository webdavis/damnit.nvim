-- Every mapping in every buffer this plugin owns, one table per filetype.
--
-- The description beside each key is what `g?` shows, so the help and the
-- mappings cannot drift apart.

local M = {}

---@param name string
---@param heading string
---@return fun()
local function jump(name, heading)
  return function()
    require("damnit.actions").jump_to_section(name, heading, vim.v.count1)
  end
end

---@param fn string the name of a function on damnit.actions
---@return fun()
local function act(fn)
  return function()
    require("damnit.actions")[fn]()
  end
end

---@type table<string, { [1]: string, [2]: string, [3]: fun(), [4]: string }[]>
M.MAPS = {
  damstatus = {
    { "n", "R", act("refresh"), "re-read the status" },
    { "n", "gu", jump("working", "Working"), "jump to Working" },
    { "n", "gs", jump("staged", "Staged"), "jump to Staged" },
    { "n", "gp", jump("unpushed", "Unpushed"), "jump to Unpushed" },
    { "n", "gn", jump("notices", "Notices"), "jump to Notices" },
    { "n", "gc", jump("conflicts", "Conflicts"), "jump to Conflicts" },
    { "n", "<C-c>", act("cancel"), "cancel the running operation" },
    { "n", "q", act("close"), "close the window" },
    { "n", "gq", act("close"), "close the window" },
    {
      "n",
      "g?",
      function()
        require("damnit.actions").help("damstatus")
      end,
      "show this help",
    },
  },
}

--- Put one filetype's mappings on a buffer.
---@param buf integer
---@param filetype string
function M.attach(buf, filetype)
  for _, map in ipairs(M.MAPS[filetype] or {}) do
    vim.keymap.set(map[1], map[2], map[3], { buffer = buf, nowait = true, desc = "dam: " .. map[4] })
  end
end

return M
