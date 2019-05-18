local screen = require("screen")
local event = require("event")

-- Variables --
local openedPrograms = {}

-- The API itself --
local system = {}


local function renderTabs()

end

-- TODO create a thread to handle all key inputs and pass onto the apps

-- The main system loop, primarily deals with
-- rendering the tabs and the current program container
function system.mainLoop()
  screen.resetPalette()

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