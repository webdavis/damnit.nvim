local fake_process = require("helpers.fake_process")
local function queue()
  return require("damnit").app().queue
end
local damnit = require("damnit")

local function with_fake(run, opts)
  local fake = fake_process.install(opts)

  local notifications = fake.said

  local ok, err = pcall(run, fake, notifications)

  fake_process.remove(fake)
  damnit.options.store = nil

  assert(ok, err)
end

local function entry(args, extra)
  return vim.tbl_extend("force", { args = args, label = table.concat(args, " ") }, extra or {})
end
return { queue = queue, with_fake = with_fake, entry = entry }
