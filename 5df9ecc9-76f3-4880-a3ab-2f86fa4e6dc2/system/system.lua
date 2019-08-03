local screen = require("screen")
local event = require("event")
local eventing = require("eventing")
local GUI = require("GUI")

-- Optimizations for lua --
local unpack = unpack or table.unpack
local remove = table.remove

-- Variables --
local openedPrograms = {}

-- The API itself --
local system = {}

system.container = GUI.createContainer(1, 1, screen.getWidth(), screen.getHeight())
system.loop = eventing.EventLoop:create()

function system.addContainer(container)
  system.container:addChild(container)
end

-- Event handler for system --
function system.processEvents(eventID, ...)
  if not eventID then return end -- Can be nil if no event was pulled for some time

  system.container:eventHandler(eventID, ...)
  system.container:draw()
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
local function createMsgBox(color, ...)
  local args = {...}
	for i = 1, #args do
		if type(args[i]) == "table" then
      -- args[i] = text.serialize(args[i], true)
      args[i] = "<Table>" -- TODO
		else
			args[i] = tostring(args[i])
		end
	end
	if #args == 0 then args[1] = "nil" end

  local alertContainer = GUI.createContainer(0, 0, screen.getWidth(), screen.getHeight())
  local startY = screen.getHeight() / 2 - 5
  alertContainer.stealAllEvents = true

  -- Button and label --
  local okButton = GUI.createButton(screen.getWidth() * 0.75, startY + 7, 14, 1, "OK", 
    color, 0xEEEEEE, color, 0xFFFFFF)
  local textbox = GUI.createTextBox(screen.getWidth() * 0.15, startY + 3,
    #args > 1 and "\"" .. table.concat(args, "\", \"") .. "\"" or args[1], 0xFFFFFF, screen.getWidth() * 0.7, 3)

  -- Event handlers, textbox used to intercept global keypresses --
  okButton.onClick = function()
    alertContainer.remove()
    system.container.skipDraw = false
  end
  textbox.eventHandler = function(_, ...) -- Used for checking global keypress
    if select(1, ...) == "key_down" and select(3, ...) == 13 then -- Enter
      okButton.onClick() end
  end

  alertContainer:addChild(textbox)
  alertContainer:addChild(okButton)
  alertContainer.drawObject = function(container)
    screen.clear(0x0, 0.5) -- Darken background
    screen.setBackground(0x111111)
    screen.drawRectangle(1, startY + 1, screen.getWidth(), 8)
    screen.setBackground(color)
    screen.drawBrailleRectangle(1, startY + 1, screen.getWidth() / 3, 0.5)
  end

  system.container.skipDraw = false
  system.addContainer(alertContainer)
  system.container:draw()
  system.container.skipDraw = true
end

function system.alert(...) createMsgBox(GUI.INFO_COLOR, ...) end
function system.warn(...)  createMsgBox(GUI.WARN_COLOR, ...) end

system.doTerm = false

-- TODO add everything to main system container!

-- Execute the main system loop
function system.mainLoop()
  -- Palette needs to be reset on startup as it is presistent
  screen.resetPalette()
  screen.clear()
  screen.update(true) -- Force update screen after reboot

  system.loop.signals:addGlobalListener(function(...)
    system.processEvents(...)
  end)

  local button = GUI.createButton(20, 30, 10, 3, "Alert", 0xFFFFFF, 0x0,  0xFF0000, 0x0, 0xFFF000)
  button.onClick = function() 
    system.warn("Hello there") 
    -- button.hidden = true
  end
  system.container:addChild(button)

  system.loop:start()

  --   if system.doTerm then
  --     local result, reason = xpcall(require("shell").getShell(), function(msg)
  --       return tostring(msg).."\n"..debug.traceback()
  --     end)
  --     if not result then
  --       io.stderr:write((reason ~= nil and tostring(reason) or "unknown error") .. "\n")
  --       io.write("Press any key to continue.\n")
  --       os.sleep(0.5)
  --       require("event").pull("key")
  --     end
  --   else
  --     screen.clear()
  --     screen.update(true)
  --     require("event").pull("key")
  --   end
  -- end
end

return system