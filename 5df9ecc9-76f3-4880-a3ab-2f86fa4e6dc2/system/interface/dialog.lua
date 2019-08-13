-- System dialogs like alert() and stuff  --
-- This file is loaded by system API only --
local screen = require("screen")
local GUI = require("GUI")
local eventing = require("eventing")

local settings = nil -- Placeholder for system settings
local system = nil   -- Placeholder for system

local function _createDialogPopupHelper(buttonText, textBoxText, color)
  local container = GUI.createContainer(0, 0, screen.getWidth(), screen.getHeight())
  local startY = screen.getHeight() / 2 - 5
  container.blockEvents = true

  -- Button and label --
  local okButton = GUI.createButton(screen.getWidth() * 0.75, startY + 7, 14, 1, buttonText, color, 0xEEEEEE, color, 0xFFFFFF)
  local textbox = GUI.createTextBox(screen.getWidth() * 0.15, startY + 3, textBoxText, 0xFFFFFF, screen.getWidth() * 0.7, 3)

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
    screen.clear(0x0, settings.interfaceTransparencyEnabled and 0.5 or 1) -- Darken background
    screen.setBackground(0x111111)
    screen.drawRectangle(1, startY + 1, screen.getWidth(), 8)
    screen.setBackground(color)
    screen.drawBrailleRectangle(1, startY + 1, screen.getWidth() / 3, 0.5)
  end

  local function drawContainer()
    system.container.skipDraw = false
    system.addContainer(container)
    system.container:draw()
    system.container.skipDraw = true
  end
  
  return container, returnedEventEmitter, close, drawContainer, startY
end

local function createMsgBox(color, buttonText, ...)
  local args = {...}
	for i = 1, #args do
    if type(args[i]) == "table" then args[i] = format.serialise(args[i], false, true, true)
		else args[i] = tostring(args[i]) end
	end
  if #args == 0 then args[1] = "nil" end
  
  local container, returnedEventEmitter, close, drawContainer = 
    _createDialogPopupHelper(buttonText, #args > 1 and "\"" .. table.concat(args, "\", \"") .. "\"" or args[1], color)
  drawContainer()
  return returnedEventEmitter
end

local function alert(...)
  createMsgBox(GUI.DISABLED_COLOR_2, "OK", ...)
end

local function successDialog(...)
  createMsgBox(GUI.SUCCESS_COLOR, "OK", ...)
end

local function infoDialog(...)
  createMsgBox(GUI.INFO_COLOR, "OK", ...)
end

local function warningDialog(...)
  createMsgBox(GUI.WARN_COLOR, "OK", ...)
end

local function errorDialog(...)
  createMsgBox(GUI.ERROR_COLOR, "OK", ...)
end

local function confirmDialog(text, color)
  local container, returnedEventEmitter, close, drawContainer, startY = _createDialogPopupHelper("OK", text, color)
  local cancelButton = GUI.createButton(screen.getWidth() * 0.75 - 16, startY + 7, 14, 1, "CANCEL", color, 0xEEEEEE, color, 0xFFFFFF)
  cancelButton.onClick = function() close(false) end
  container:addChild(cancelButton)
  drawContainer()
  return returnedEventEmitter
end

local function syncifyDialogBox(eventEmitter)
  local continue, returned = true, nil
  eventEmitter:addGlobalListener(function(...) 
    continue, returned = false, {...}
  end)
  while continue do system.processEvents(event.pull()) end
  return returned
end

-- This function adds the above functionality to
-- the system table
local function addFunctionsToSystem(_system, _settings)
  system, settings = _system, _settings
  system.createMsgBox = createMsgBox
  system.alert = alert
  system.successDialog = successDialog
  system.infoDialog = infoDialog
  system.warningDialog = warningDialog
  system.errorDialog = errorDialog
  system.confirmDialog = confirmDialog
  system.syncifyDialogBox = syncifyDialogBox
end

return addFunctionsToSystem
