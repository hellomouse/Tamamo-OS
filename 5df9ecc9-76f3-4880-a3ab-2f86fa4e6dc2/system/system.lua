local screen = require("screen")

-- Variables --
local openedPrograms = {}

-- The API itself --
local system = {}


local function renderTabs()

end

-- The main system loop, primarily deals with
-- rendering the tabs and the current program container
function system.mainLoop()
  while true do
    local result, reason = xpcall(require("shell").getShell(), function(msg)
      return tostring(msg).."\n"..debug.traceback()
    end)
    if not result then
      io.stderr:write((reason ~= nil and tostring(reason) or "unknown error") .. "\n")
      io.write("Press any key to continue.\n")
      os.sleep(0.5)
      require("event").pull("key")
    end
  end
end


return system