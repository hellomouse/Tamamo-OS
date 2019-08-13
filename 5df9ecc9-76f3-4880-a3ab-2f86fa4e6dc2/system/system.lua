local screen = require("screen")
local event = require("event")
local eventing = require("eventing")
local GUI = require("GUI")
local format = require("format")

-- Optimizations for lua --
local unpack = unpack or table.unpack
local remove = table.remove

-- Variables --
local openedPrograms = {}
local settings = {}
local backgroundContainers = {}

-- The API itself --
local system = {}

system.container = GUI.createContainer(1, 1, screen.getWidth(), screen.getHeight())
system.loop = eventing.EventLoop:create()

function system.addContainer(container)
  system.container:addChild(container)
end

-- System settings --
function system.getDefaultUserSettings()
	return {
		localizationLanguage = "English",

		timeFormat = "%d %b %Y %H:%M:%S",
		timeRealTimestamp = true,
		timeTimezone = 0,

		networkUsers = {},
		networkName = "Computer #" .. string.format("%06X", math.random(0x0, 0xFFFFFF)),
		networkEnabled = true,
		networkSignalStrength = 512,
		networkFTPConnections = {},
		
		interfaceWallpaperEnabled = false,
		interfaceWallpaperPath = "",
		interfaceWallpaperMode = 1,
		interfaceWallpaperBrightness = 0.9,

		interfaceScreensaverEnabled = false,
		interfaceScreensaverPath = "",
		interfaceScreensaverDelay = 20,
		
		interfaceTransparencyEnabled = true,
		interfaceTransparencyDock = 0.4,
		interfaceTransparencyMenu = 0.2,
		interfaceTransparencyContextMenu = 0.2,

		interfaceColorDesktopBackground = 0x1E1E1E,
		interfaceColorDock = 0xE1E1E1,
		interfaceColorMenu = 0xF0F0F0,
		interfaceColorDropDownMenuSeparator = 0xA5A5A5,
		interfaceColorDropDownMenuDefaultBackground = 0xFFFFFF,
		interfaceColorDropDownMenuDefaultText = 0x2D2D2D,

		filesShowExtension = false,
		filesShowHidden = false,
		filesShowApplicationIcon = true,

		iconWidth = 12,
		iconHeight = 6,
		iconHorizontalSpace = 1,
		iconVerticalSpace = 1,
		
		tasks = {},
		dockShortcuts = {
			--filesystem.path(paths.system.applicationAppMarket),
			--filesystem.path(paths.system.applicationMineCodeIDE),
			--filesystem.path(paths.system.applicationFinder),
			--filesystem.path(paths.system.applicationPictureEdit),
			--filesystem.path(paths.system.applicationSettings),
		},
		extensions = {
			--[".lua"] = filesystem.path(paths.system.applicationMineCodeIDE),
			--[".cfg"] = filesystem.path(paths.system.applicationMineCodeIDE),
			--[".txt"] = filesystem.path(paths.system.applicationMineCodeIDE),
		--	[".lang"] = filesystem.path(paths.system.applicationMineCodeIDE),
		--	[".pic"] = filesystem.path(paths.system.applicationPictureEdit),
		--	[".3dm"] = paths.system.applications .. "3D Print.app/"
		},
	}
end

-- TODO remove
settings = system.getDefaultUserSettings()

-- Event handler for system --
function system.processEvents(eventID, ...)
  if not eventID then return end -- Can be nil if no event was pulled for some time
  local processEventsAfterThisIndex = 0

  -- Event blocking containers do not update lower containers --
  -- Locate the highest container which for to use a container for --
  for i = #backgroundContainers, 1, -1 do
    if backgroundContainers[i].blockEvents then
      processEventsAfterThisIndex = i
      break
    end
  end

  -- Process Events --
  if processEventsAfterThisIndex <= 0 then
    system.container:eventHandler(eventID, ...)
  end
  for i = processEventsAfterThisIndex or 1, #backgroundContainers do
    if backgroundContainers[i] ~= nil then
      backgroundContainers[i]:eventHandler(eventID, ...)
    end
  end

  -- Draw containers bottom up --
  system.container:draw()
  for i = 1, #backgroundContainers do
    if backgroundContainers[i] ~= nil then
      backgroundContainers[i]:draw()
    end
  end
end

-- Short cut for attach / detach timer
function system.attachTimer(timer)
  if timer == nil then return end
  system.loop:attachTimer(timer)
end

function system.detachTimer(timer)
  if timer == nil then return end
  system.loop:detachTimer(timer)
end

-- Running and erroring programs
-- This is totally stolen from MineOS credits to them for this code
function system.call(func, ...)
  local args = {...}
	local function runFunc()
		func(table.unpack(args))
	end

	local function tracebackMethod(xpcallTraceback)
		local traceback, info, firstMatch = tostring(xpcallTraceback) .. "\n" .. debug.traceback()
		for runLevel = 0, math.huge do
      info = debug.getinfo(runLevel)
      if not info then error("Failed to get debug info for runlevel " .. runLevel) end
      if (info.what == "main" or info.what == "Lua") and info.source ~= "=machine" then
        if firstMatch then
          return { path = info.source:sub(2, -1),
                   line = info.currentline,
                   traceback = traceback }
        else firstMatch = true end
      end
		end
	end
	
	local xpcallSuccess, xpcallReason = xpcall(runFunc, tracebackMethod)
  if type(xpcallReason) == "string" or type(xpcallReason) == "nil" then
    -- TODO FIX THIS
		xpcallReason = {
			path = paths.system.libraries .. "System.lua",
			line = 1,
			traceback = "system fatal error: " .. tostring(xpcallReason)
		}
	end

	if not xpcallSuccess and not xpcallReason.traceback:match("^table") and not xpcallReason.traceback:match("interrupted") then
		return false, xpcallReason.path, xpcallReason.line, xpcallReason.traceback
	end
	return true
end

function system.error(path, line, traceback)
  require("component").ocemu.log("ERRORED")
  local errorContainer = GUI.createContainer(0, screen.getHeight() / 4, screen.getWidth(), screen.getHeight() / 2)

  errorContainer:addChild(GUI.createLabel(15, 1, "MC 01:00 AM", 0xFF0000, 15, 5, GUI.ALIGN_TOP_LEFT))
  errorContainer.drawObject = function(container)
    screen.clear(0x0, 0.5)
    screen.set(1, 20, "hello world")
  end

  system.addContainer(errorContainer)
end

function system.execute(func, ...)
  local success, path, line, traceback = system.call(func, ...)
  if not success then system.error(path, line, traceback) end
end

function system.executeProgram(programPath)

end

-- System popups --
local function addCloseableContainer(container)
  container.blockEvents = true

  -- Add to free spot, or if none then to end of table
  local n = #backgroundContainers
  local indexToAddAt = n + 1
  for i = 1, n do
    if backgroundContainers[i] == nil then
      indexToAddAt = i
    end
  end
  backgroundContainers[indexToAddAt] = container

  -- Return a function to close the container --
  local function close()
    backgroundContainers[indexToAddAt] = nil
  end

  return close, indexToAddAt
end


-- Add dialog functionality to system --
require("/system/interface/dialog.lua")(system, settings)

system.doTerm = true



-- Execute the main system loop
function system.mainLoop()
  -- Palette needs to be reset on startup as it is presistent
  screen.resetPalette()
  screen.clear()
  screen.update(true) -- Force update screen after reboot

  -- -- Start OS code
  system.loop.signals:addGlobalListener(function(...)
    system.processEvents(...)
  end)

  local button = GUI.createButton(20, 30, 10, 3, "Alert", 0xFFFFFF, 0x0,  0xFF0000, 0x0, 0xFFF000)
  button.onClick = function()
    local e = system.confirmDialog("Hello", GUI.ERROR_COLOR)
    e:on("ok", function() system.successDialog("You clicked ok!") end)
    e:on("cancel", function() system.errorDialog("WHY U CANCEL") end)
    -- system.createMessageBox(GUI.ERROR_COLOR, "(x) Doubt", "⢹⣀⣀⣀⣀⣀⣀\n⢸⣷⣾⣀⣸⠰⢾   This is supposed to be a GPU\n⠘⠉⠛⠛⠙⠋⠉", {a = "b"})
    -- button.hidden = true
  end
  system.container:addChild(button)
  system.container:addChild(GUI.createSwitch(30, 40, 0x333333, 0xFF0000, 0xFFFFFF))
  system.container:addChild(GUI.createProgressIndicator(3, 22, 0x333333, 0xFF0000, 0xFFAA00))





  local buttonText, textBoxText, color = "test", "idk lmao", 0xFFFF00
  local container = GUI.createContainer(0, 40, screen.getWidth(), screen.getHeight() / 2)
  local startY = screen.getHeight() / 2 - 5
  container.blockEvents = true

  -- Button and label --
  local okButton = GUI.createButton(screen.getWidth() * 0.75, 2, 14, 1, buttonText, color, 0xEEEEEE, color, 0xFFFFFF)
  local textbox = GUI.createTextBox(screen.getWidth() * 0.15, 2, textBoxText, 0xFFFFFF, screen.getWidth() * 0.7, 3)

  -- Event handlers, textbox used to intercept global keypresses --
  local returnedEventEmitter = eventing.EventEmitter:create()
  local function close(success)
    container.remove()
    system.container.skipDraw = false
    returnedEventEmitter:emit(success and "ok" or "cancel")
  end

  okButton.onClick = function() close(true) end
  textbox.eventHandler = function(_, ...) -- Used for checking global keypress
    if select(1, ...) == "key_down" and select(3, ...) == 13 then -- Enter
      okButton.onClick() end
  end

  container:addChild(textbox)
  container:addChild(okButton)
  container.drawObject = function(container)
    screen.setBackground(0x111111)
    screen.drawRectangle(1, startY + 1, screen.getWidth(), 8)
    screen.setBackground(color)
    screen.drawBrailleRectangle(1, startY + 1, screen.getWidth() / 3, 0.5)
  end

  -- addCloseableContainer(container)

  system.loop:start()

  -- -- Start normal code

  -- if system.doTerm then
  --   local result, reason = xpcall(require("shell").getShell(), function(msg)
  --     return tostring(msg).."\n"..debug.traceback()
  --   end)
  --   if not result then
  --     io.stderr:write((reason ~= nil and tostring(reason) or "unknown error") .. "\n")
  --     io.write("Press any key to continue.\n")
  --     os.sleep(0.5)
  --     require("event").pull("key")
  --   end
  -- else
  --   screen.clear()
  --   screen.update(true)
  --   require("event").pull("key")
  -- end
end

return system