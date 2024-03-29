do
  local loadfile = load([[return function(file)
    local pc,cp = computer or package.loaded.computer, component or package.loaded.component
    local addr, invoke = pc.getBootAddress(), cp.invoke
    local handle, reason = invoke(addr, "open", file)
    assert(handle, reason)
    local buffer = ""
    repeat
      local data, reason = invoke(addr, "read", handle, math.huge)
      assert(data or not reason, reason)
      buffer = buffer .. (data or "")
    until not data
    invoke(addr, "close", handle)
    return load(buffer, "=" .. file, "bt", _G)
  end]], "=loadfile", "bt", _G)()
  loadfile("/lib/core/boot.lua")(loadfile)
end

local system = require("/system/system.lua")
system.mainLoop()