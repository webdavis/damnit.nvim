local function queue()
  return require("damnit").app().queue
end
local function entry(args, extra)
  return vim.tbl_extend("force", { args = args, label = table.concat(args, " ") }, extra or {})
end
return { queue = queue, entry = entry }
