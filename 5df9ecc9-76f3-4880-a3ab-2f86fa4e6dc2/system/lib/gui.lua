local screen = require("screen")
local unicode = require("unicode")
local thread = require("thread")
local color = require("color")
local format = require("format")

-- Returned object
local GUI = {
  ALIGN_TOP_LEFT = 1,
  ALIGN_TOP_MIDDLE = 2,
  ALIGN_TOP_RIGHT = 3,
  ALIGN_MIDDLE_LEFT = 4,
  ALIGN_MIDDLE_MIDDLE = 5,
  ALIGN_MIDDLE_RIGHT = 6,
  ALIGN_BOTTOM_LEFT = 7,
  ALIGN_BOTTOM_MIDDLE = 8,
  ALIGN_BOTTOM_RIGHT = 9,

  DISABLED_COLOR_1 = 0x5A5A5A,
  DISABLED_COLOR_2 = 0x878787,

  BASE_ANIMATION_STEP = 0.05,

  BUTTON_ANIMATION_DURATION = 0.2,

  INPUT_LEFT_RIGHT_TOTAL_PAD = 2,

  KEYBOARD_CHARS = " --~!@#$%^&*()_+-=`?><\":{}|[\\]';/.,",

  -- Cursor blinking for inputs
  CURSOR_CHAR = " ",         -- This value changes back and forth
  CURSOR_BLINK = 0xF49241, 
  CURSOR_BLINK_DURATION = 0.5,

  -- Progress indicator
  PROGRESS_WIDTH = 10,
  PROGRESS_HEIGHT = 1,
  PROGRESS_DELAY = 0.05
}

-- Optimization for lua
local len = unicode.len
local sub = unicode.sub
local char = string.char
local rep = string.rep

local insert = table.insert
local remove = table.remove

local floor = math.floor
local ceil = math.ceil
local min = math.min

-- Global cursor blink update
-- TODO move this to some animation object
thread.create(function()
  local isCursorOn = false
  while true do
    if isCursorOn then GUI.CURSOR_CHAR  = "▌"
    else GUI.CURSOR_CHAR = "" end

    isCursorOn = not isCursorOn
    os.sleep(GUI.CURSOR_BLINK_DURATION)
  end 
end)


-- Global functions like alert()
function GUI.alert(message)
  screen.resetDrawingBound()
  screen.setBackground(0x0)

end

-- Base application tab class


-- Base container class
GUIContainer = {}
GUIContainer.__index = GUIContainer

function GUIContainer:create(x, y, width, height, scrollable, autoScrollX, autoScrollY)
  local obj = {}                  -- New object
  setmetatable(obj, GUIContainer) -- make GUIContainer handle lookup

  obj.x, obj.y, obj.width, obj.height = x, y, width, height
  obj.scrollable = scrollable
  obj.autoScrollX = autoScrollX
  obj.autoScrollY = autoScrollY
  obj.scrollX = 0
  obj.scrollY = 0
  obj.children = {}
  obj.type = "GUIContainer"
  return obj
end

function GUIContainer:findChild(obj)
  for i = 1, #self.children do
    if self.children[i] == obj then return i end
  end
end

function GUIContainer:addChild(guiObject, index)
  -- Add properties
  guiObject.localX = guiObject.x
  guiObject.localY = guiObject.y
  guiObject.parent = self

  -- Convert local coords to global
  guiObject.x = self.x + guiObject.x
  guiObject.y = self.y + guiObject.y

  -- Wrap draw function to respect parent boundary
  if guiObject.draw then
    local tempdraw = guiObject.draw
    guiObject.draw = function(obj)
      obj.parent:setBounds() -- Limit bounds by the parent

      -- Update local coordinates
      obj.localX = obj.x - obj.parent.x
      obj.localY = obj.y - obj.parent.y
      tempdraw(obj)
    end
  end

  -- Set index properties
  guiObject.getIndex = function() return self:findChild(guiObject) end
  guiObject.moveForward = function()
    local newIndex = self:findChild(guiObject) + 1
    if newIndex > #self.children then newIndex = #self.children end
    self.children:add(guiObject.remove(), newIndex)
  end
  guiObject.moveBackward = function()
    local newIndex = self:findChild(guiObject) - 1
    if newIndex < 1 then newIndex = 1 end
    self.children:add(guiObject.remove(), newIndex)
  end
  guiObject.moveToFront = function() self.children:add(guiObject.remove()) end
  guiObject.moveToBack =  function() self.children:add(guiObject.remove(), 1) end
  guiObject.remove = function() return self.children:remove(self:findChild(guiObject)) end

  if index == nil then insert(self.children, guiObject)
  else insert(self.children, guiObject, index) end
end

function GUIContainer:removeChild(index)
  remove(self.children, index)
end

function GUIContainer:draw()
  -- TODO scrollbars and shit
  screen.setDrawingBound(self.x, self.y, self.x + self.width - 1, self.y + self.height - 1, true)
  self.boundX1, self.boundY1, self.boundX2, self.boundY2 = screen.getDrawingBound()

  for i = 1, #self.children do
    -- Don't render hidden elements
    if self.children[i].hidden then goto continue end

    -- GUI Containers already set their drawing bounds, otherwise
    -- we need to restrict drawing bounds for them
    if self.children[i].type == "GUIContainer" then
      self.children[i].draw(self.children[i])
    else
      screen.setDrawingBound(self.children[i].x, self.children[i].y, 
        self.children[i].x + self.children[i].width, self.children[i].y + self.children[i].height)
      self.children[i].draw(self.children[i])
    end

    screen.setDrawingBound(self.boundX1, self.boundY1, self.boundX2, self.boundY2)
    ::continue::
  end
end

function GUIContainer:setBounds()
  screen.setDrawingBound(self.boundX1, self.boundY1, self.boundX2, self.boundY2)
end

function GUIContainer:eventHandler(...)
  for i = 1, #self.children do
    self.children[i]:eventHandler(...)
  end
end

-- Wrapper to create a GUIContainer --
function GUI.createContainer(x, y, width, height, scrollable, autoScrollX, autoScrollY)
  return GUIContainer:create(x, y, width, height, scrollable, autoScrollX, autoScrollY)
end







-- Base GUI Object class
------------------------------------------------
GUIObject = {}
GUIObject.__index = GUIObject

function GUIObject:create(x, y, width, height)
  local obj = {}               -- New object
  setmetatable(obj, GUIObject) -- make GUIObject handle lookup

  obj.x, obj.y, obj.width, obj.height = x, y, width, height
  obj.disabled, obj.hidden = false, false
  obj.type = "GUIObject"
  obj.eventHandler = nil  -- Runs when event is called, override

  return obj
end

function GUIObject:eventHandler(...)
  -- Default: no event handler
end


-- Base Animation class
------------------------------------------------
Animation = {}
Animation.__index = Animation

function Animation:create(aniFunction, stepSize, GUIObj)
  local obj = {}               -- New object
  setmetatable(obj, Animation) -- make Animation handle lookup

  if stepSize <= 0 then
    error("stepSize must be greater than 0") end

  obj.aniFunction = aniFunction
  obj.stepSize = stepSize
  obj.GUIObj = GUIObj
  obj.thread = nil
  return obj
end

function Animation:start(duration, delay)
  if delay == nil then delay = 0 end
  if self.thread ~= nil then self:stop() end

  self.thread = thread.create(function(GUIObj, duration, delay)
    os.sleep(delay)
    local i = 0
    while i < duration do
      self.aniFunction(GUIObj, i / duration, self)
      os.sleep(self.stepSize)
      i = i + self.stepSize
    end
    self:stop(1)
  end, self.GUIObj, duration, delay)
end

-- Pause, resume and stop animation
function Animation:pause()  self.thread:suspend() end
function Animation:resume() self.thread:resume() end
function Animation:stop(percentDone)
  if percentDone == nil then percentDone = 0 end

  self.aniFunction(self.GUIObj, percentDone) -- Reset animation to initial state
  self.thread:kill()
  self.thread = nil
end

-- Panel --
------------------------------------------------
local function drawPanel(panel)
  local bx1, by1, bx2, by2
  if panel.overrideBound then
    screen.setDrawingBound(panel.x, panel.y, panel.x + panel.width - 1, panel.y + panel.height - 1, false)
    bx1, by1, bx2, by2 = screen.getDrawingBound()
  end

  screen.setBackground(panel.color)
  screen.drawRect(panel.x, panel.y, panel.width, panel.height, panel.bgAlpha)
  panel.container:draw()

  -- Reset original bounds
  screen.setDrawingBound(bx1, by1, bx2, by2)
end

local function panelEventHandler(panel, ...)
  panel.container:eventHandler(...)
end

function GUI.createPanel(x, y, width, height, bgColor, bgAlpha, margin, overrideBound)
  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, width, "number")
  checkArg(4, height, "number")
  checkArg(5, bgColor, "number")

  if bgAlpha == nil then bgAlpha = 1 end
  if margin == nil then margin = 0 end

  checkArg(6, bgAlpha, "number")
  checkArg(7, margin, "number")

  local panel = GUIObject:create(x, y, width, height)

  -- Basic Properties --
  panel.color = bgColor
  panel.type = "panel"
  panel.draw = drawPanel

  -- Y margin is halved since cells are 2x taller than wide
  panel.container = GUIContainer:create(x + margin, ceil(y + margin / 2), width - margin * 2, height - margin)
  panel.overrideBound = overrideBound

  -- Functions --
  panel.addChild = function(guiObj, index) panel.container:addChild(guiObj, index) end
  panel.removeChild = function(index) panel.container:removeChild(index) end
  panel.eventHandler = panelEventHandler

  return panel
end

-- Image wrapper --
------------------------------------------------
local function drawImage(img)
  img.loaded:draw(img.x, img.y)
end

function GUI.createImage(x, y, loadedImage)
  checkArg(1, x, "number")
  checkArg(2, y, "number")

  local img = GUIObject:create(x, y, loadedImage.width, loadedImage.height)
  img.type = "image"
  img.draw = drawImage
  img.loaded = loadedImage

  return img
end

-- Text Box --
------------------------------------------------
local function drawTextBox(textbox)
  screen.setForeground(textbox.color)

  -- Textbox text should wrap around
  for i = 1, #textbox.lines do
    screen.drawText(textbox.x, textbox.y + i - 1, textbox.lines[i], 1, true)
  end
end

function GUI.createTextBox(x, y, text, textColor, width, height)
  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, text, "string")
  checkArg(4, textColor, "number")

  -- Height of the "text", not necessarily the label boundary
  local textWidth, textHeight

  -- Auto width and height if width is "auto" or nil (same for height)
  if width == nil or width == "auto" then
    width, height = len(text), 1
    textWidth, textHeight = width, height
  elseif height == nil or height == "auto" then
    text, height = format.wrap(text, width)
    textWidth, textHeight = min(width, len(text)), height
  else
    text, textHeight = format.wrap(text, width)
    textWidth = min(width, len(text))
  end

  local textbox = GUIObject:create(x, y, width, height)

  -- Basic Properties --
  textbox.lines = {}
  local i = 1
  for s in text:gmatch("[^\r\n]+") do
    textbox.lines[i] = s
    i = i + 1
  end

  textbox.align = align
  textbox.color = textColor

  -- Additional textbox properties --
  textbox.type = "textbox"
  textbox.draw = drawTextBox
  textbox.textWidth = textWidth
  textbox.textHeight = textHeight

  return textbox
end


-- Text Labels --
------------------------------------------------
local function drawLabel(label)
  -- 0 = top/left, 1 = middle, 2 = bottom/right
  local ALIGN_X, ALIGN_Y = label.align % 3, floor(label.align / 3)
  local x, y

  -- Calculate x alignment
  if ALIGN_X == 1 then x = label.x + (label.width - label.textWidth) / 2   -- Middle
  elseif ALIGN_X == 2 then x = label.x + label.width - label.textWidth     -- Right
  else x = label.x end -- Left

  -- Calculate y alignment
  if ALIGN_Y == 1 then y = label.y + (label.height - label.textHeight) / 2 -- Middle
  elseif ALIGN_Y == 2 then y = label.y + label.height - label.textHeight   -- Bottom
  else y = label.y end -- Top

  screen.setForeground(label.color)
  screen.drawText(x, y, label.text, 1, true)
end

function GUI.createLabel(x, y, text, textColor, width, height, align)
  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, text, "string")
  checkArg(4, textColor, "number")

  -- Alignment (default to top left)
  if not align then align = GUI.ALIGN_TOP_LEFT end

  -- Height of the "text", not necessarily the label boundary
  local textWidth, textHeight

  -- Auto width and height if width is "auto" or nil (same for height)
  if width == nil or width == "auto" then
    width, height = len(text), 1
    textWidth, textHeight = width, height
  elseif height == nil or height == "auto" then
    text, height = format.wrap(text, width)
    textWidth, textHeight = min(width, len(text)), height
  else
    text, textHeight = format.wrap(text, width)
    textWidth = min(width, len(text))
  end

  local label = GUIObject:create(x, y, width, height)

  -- Basic Properties --
  label.text = text
  label.align = align
  label.color = textColor

  -- Additional label properties --
  label.type = "label"
  label.draw = drawLabel
  label.textWidth = textWidth
  label.textHeight = textHeight

  return label
end

-- Switchs --
------------------------------------------------

-- Switch animation (Fade)
local function switchAnimation(switch, percentDone, animation)
  -- If switch is on head towards dx = width, otherwise
  -- do the exact opposite
  if switch.toggled then 
    switch.animationdx = ceil(switch.width * percentDone) - 1
  else switch.animationdx = ceil(switch.width * (1 - percentDone)) - 1 end

  -- Quick fix for out of bounds
  if switch.animationdx < 0 then switch.animationdx = 0 
  elseif switch.animationdx > switch.width - 2 then switch.animationdx = switch.width - 2 end
  
  switch.draw(switch) -- Update appearance
end

-- Switch drawing function --
local function drawSwitch(switch)
  screen.setBackground(switch.inactiveColor)
  screen.drawText(switch.x, switch.y, "     ")

  screen.setBackground(switch.activeColor)
  screen.drawText(switch.x, switch.y, rep(" ", switch.animationdx))

  screen.setBackground(switch.cursorColor)
  screen.drawText(switch.x + switch.animationdx, switch.y, "  ")
end

-- Event handler for switch, deals only with touch events for now --
local function switchEventHandler(switch, ...)
  if switch.disabled then return end -- Ignore event handling for disabled switches
  if select(1, ...) == "touch" then
    -- Check bounds for touch
    local x, y = select(3, ...), select(4, ...)
    if x < switch.x or x > switch.x + switch.width or
       y < switch.y or y > switch.y + switch.height then
        return
    end

    -- Invert the toggled boolean
    switch.toggled = not switch.toggled
    if switch.onChange then -- Call onchange function
      switch.onChange(switch, ...) end
    switch.animation:start(switch.animationDuration)
  end
end

function GUI.createSwitch(x, y, inactiveColor, activeColor, cursorColor)
  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, inactiveColor, "number")
  checkArg(4, activeColor, "number")
  checkArg(5, cursorColor, "number")

  local switch = GUIObject:create(x, y, 5, 1)
  
  -- Basic Properties --
  switch.inactiveColor, switch.activeColor = inactiveColor, activeColor
  switch.cursorColor = cursorColor

  -- Additional switch properties --
  switch.toggled = false
  switch.disabled = false
  switch.animationDuration = GUI.BUTTON_ANIMATION_DURATION
  switch.type = "switch"
  switch.eventHandler = switchEventHandler
  switch.onChange = nil
  switch.draw = drawSwitch
  switch.animationdx = 0
  switch.animation = Animation:create(switchAnimation, GUI.BASE_ANIMATION_STEP, switch)
  switch.setState = function(state)
    switch.toggled = state
    switch.animation:start(switch.animationDuration)
  end

  return switch
end

-- Buttons --
------------------------------------------------

-- Button animation (Fade)
local function buttonAnimation(button, percentDone, animation)
  -- Switch buttons fade directly to the new state
  if button.switchMode then
    if button.pressed then -- Fade towards "on" state
      button.currentColor = color.transition(button.buttonColor, button.pressedColor, percentDone)
      button.currentTextColor = color.transition(button.textColor, button.textPressedColor, percentDone)
    else
      button.currentColor = color.transition(button.buttonColor, button.pressedColor, 1 - percentDone)
      button.currentTextColor = color.transition(button.textColor, button.textPressedColor, 1 - percentDone)
    end

  -- Normal buttons fade to the max percent then fade out
  else   -- Fade towards on state
    if percentDone < 0.5 then
      button.currentColor = color.transition(button.buttonColor, button.pressedColor, 2 * percentDone)
      button.currentTextColor = color.transition(button.textColor, button.textPressedColor, 2 * percentDone)
    else -- Fade away from on state to original state
      button.currentColor = color.transition(button.buttonColor, button.pressedColor, 1 - 2 * (percentDone - 0.5))
      button.currentTextColor = color.transition(button.textColor, button.textPressedColor, 1 - 2 * (percentDone - 0.5))
    end
  end
  button.draw(button) -- Update appearance
end

-- Set the background / foreground colors depending on
-- the button object (isPressed)
local function setButtonColors(button)
  if button.disabled then -- Forcibly override style for disabled buttons
    button.currentColor = GUI.DISABLED_COLOR_1
    button.currentTextColor = GUI.DISABLED_COLOR_2
  end

  screen.setBackground(button.currentColor)
  screen.setForeground(button.currentTextColor)
end

-- Button drawing function --
local function drawButton(button)
  setButtonColors(button)

  -- Framed buttons do not get the solid fill
  if button.framed then
    screen.drawRectOutline(button.x, button.y, button.width, button.height, button.bgAlpha)
    screen.drawText(button.x + button.width / 2 - len(button.text) / 2, button.y + button.height / 2, button.text, 1, true)
  else  
    screen.drawRect(button.x, button.y, button.width, button.height, button.bgAlpha)
    screen.drawText(button.x + button.width / 2 - len(button.text) / 2, button.y + button.height / 2, button.text)
  end
end

-- Event handler for button, deals only with touch events for now --
local function buttonEventHandler(button, ...)
  if button.disabled then return end -- Ignore event handling for disabled buttons
  if select(1, ...) == "touch" then
    -- Check bounds for touch
    local x, y = select(3, ...), select(4, ...)
    if x < button.x or x > button.x + button.width or
       y < button.y or y > button.y + button.height then
        return
    end

    -- In switch mode, invert the pressed boolean, otherwise
    -- set it equal to true
    if not button.switchMode then button.pressed = true
    else button.pressed = not button.pressed end

    if button.onClick then -- Call onclick function
      button.onClick(button, ...) end

    button.animation:start(button.animationDuration)
  end
end

local function createButton(x, y, width, height, text, buttonColor, textColor, pressedColor, textPressedColor, bgAlpha, isFrame)
  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, width, "number")
  checkArg(4, height, "number")
  checkArg(5, text, "string")
  checkArg(6, buttonColor, "number")
  checkArg(7, textColor, "number")
  checkArg(8, pressedColor, "number")
  checkArg(9, textPressedColor, "number")

  local button = GUIObject:create(x, y, width, height)

  if bgAlpha == nil then bgAlpha = 1 end
  if len(text) > width - 2 then text = format.trimLength(text, width - 2) end

  -- Basic Properties --
  button.text = text
  button.buttonColor, button.textColor = buttonColor, textColor
  button.pressedColor, button.textPressedColor = pressedColor, textPressedColor
  button.currentColor, button.currentTextColor = buttonColor, textColor
  button.bgAlpha = bgAlpha

  -- Additional button properties --
  button.pressed = false
  button.switchMode = false
  button.disabled = false
  button.animationDuration = GUI.BUTTON_ANIMATION_DURATION
  button.type = "button"
  button.eventHandler = buttonEventHandler
  button.onClick = nil
  button.draw = drawButton
  button.framed = isFrame
  button.animation = Animation:create(buttonAnimation, GUI.BASE_ANIMATION_STEP, button)

  return button
end

function GUI.createButton(x, y, width, height, text, buttonColor, textColor, pressedColor, textPressedColor, bgAlpha)
  return createButton(x, y, width, height, text, buttonColor, textColor, pressedColor, textPressedColor, bgAlpha)
end

function GUI.createFramedButton(x, y, width, height, text, buttonColor, textColor, pressedColor, textPressedColor, bgAlpha)
  return createButton(x, y, width, height, text, buttonColor, textColor, pressedColor, textPressedColor, bgAlpha, true)
end

function GUI.createAdaptiveButton(x, y, text, buttonColor, textColor, pressedColor, textPressedColor, bgAlpha)
  local width, height = len(text) + 2, 3
  return createButton(x, y, width, height, text, buttonColor, textColor, pressedColor, textPressedColor, bgAlpha)
end

function GUI.createAdaptiveFramedButton(x, y, text, buttonColor, textColor, pressedColor, textPressedColor, bgAlpha)
  local width, height = len(text) + 2, 3
  return createButton(x, y, width, height, text, buttonColor, textColor, pressedColor, textPressedColor, bgAlpha, true)
end


-- Text input --
------------------------------------------------
local function limitCursor(input)
  if input.scroll < 0 then input.scroll = 0
  elseif input.scroll > len(input.value) - input.width + GUI.INPUT_LEFT_RIGHT_TOTAL_PAD + 1 then 
    input.scroll = len(input.value) - input.width + GUI.INPUT_LEFT_RIGHT_TOTAL_PAD + 1
    if input.scroll < 0 then input.scroll = 0 end
  end
  if input.cursor < 1 then input.cursor = 1
  elseif input.cursor > len(input.value) + 1 then input.cursor = len(input.value) + 1 end
end

local function setInputValueTo(val, input)
  if input.validate == nil or input.validate(val) then
    input.value = val
    return true
  end
  return false
end

local function addKeyToInput(input, keyCode, code)
  if keyCode == 8 or keyCode == 46 then -- Backspace and delete
    -- Since lua has negative indexes 
    if input.cursor - GUI.INPUT_LEFT_RIGHT_TOTAL_PAD < 0 then input.value = sub(input.value, 2)
    else input.value = sub(input.value, 1, input.cursor - 2) .. sub(input.value, input.cursor) end

    input.cursor = input.cursor - 1
    input.scroll = input.scroll - 1
  elseif code == 203 then -- Left arrow
    input.cursor = input.cursor - 1
    input.scroll = input.scroll - 1
  elseif code == 205 then -- Right arrow 
    input.cursor = input.cursor + 1
    input.scroll = input.scroll + 1
  elseif code == 200 and input.history then -- Up arrow
    input.historyIndex = input.historyIndex - 1
    if input.historyIndex < 1 then input.historyIndex = #input.historyArr end
    if input.historyArr[input.historyIndex] == nil then return end

    input.value = input.historyArr[input.historyIndex]
    input.scroll = 0
    input.cursor = len(input.value) + 1

  elseif code == 208 and input.history then -- Down arrow 
    input.historyIndex = input.historyIndex + 1
    if input.historyIndex > #input.historyArr then input.historyIndex = 1 end
    if input.historyArr[input.historyIndex] == nil then return end

    input.value = input.historyArr[input.historyIndex]
    input.scroll = 0
    input.cursor = len(input.value) + 1

  elseif keyCode == 13 then -- Enter
    if input.history then 
      insert(input.historyArr, input.value)

      -- Remove first element if too large
      if #input.historyArr > input.maxHistorySize then
        remove(input.historyArr, 1)
      end

      input.historyIndex = #input.historyArr
    end
    if input.onEnter then input.onEnter(input) end
  elseif code == 15 and input.nextInput then -- Tab
    input.nextInput.focused = true
    input.nextInput.draw(input.nextInput)
    input.focused = false
    input.draw(input)
  elseif char(keyCode):match("[%w]") or GUI.KEYBOARD_CHARS:match(char(keyCode)) then
    if setInputValueTo(
        sub(input.value, 1, input.cursor - 1) .. char(keyCode) .. sub(input.value, input.cursor), input) then
      input.cursor = input.cursor + 1
      if input.cursor > input.width - GUI.INPUT_LEFT_RIGHT_TOTAL_PAD then
        input.scroll = input.scroll + 1
      end
    end
  end
  limitCursor(input)
end

local function inputEventHandler(input, ...)
  if input.disabled then return end -- Ignore event handling for disabled inputs

  local event = select(1, ...)
  if event == "touch" then
    -- Check bounds for touch
    local x, y = select(3, ...), select(4, ...)
    if x < input.x or x > input.x + input.width or
       y < input.y or y > input.y + input.height then
        input.focused = false
        input.draw(input)
        return
    end

    -- Focus the input and set the cursor
    input.focused = true
    input.cursor = input.scroll + x - input.x - input.pad / 2

    limitCursor(input)

    if input.onClick then -- Call onclick function
      input.onClick(input, ...) end
    input.draw(input)
  elseif event == "key_down" and input.focused then
    addKeyToInput(input, select(3, ...), select(4, ...))

    if input.onInput then input.onInput(input, ...) end
    input.draw(input)
  elseif event == "clipboard" and input.focused then -- TODO respect cursor
    if setInputValueTo(
        sub(input.value, 1, input.cursor - 1) .. select(3, ...) .. sub(input.value, input.cursor), input) then
      input.cursor = input.cursor + len(select(3, ...)) -- Move cursor
      input.scroll = input.scroll + len(select(3, ...)) 
      limitCursor(input)
      
      if input.onPaste then input.onPaste(input, ...) end
      input.draw(input)
    end
  end
end

-- Input cursor animation (Just need to draw)
local function inputAnimation(input, percentDone, animation)
  input.draw(input) -- Update appearance
end

local function drawInput(input)
  -- Color setting
  if input.disabled then -- Forcibly override style for disabled inputs
    screen.setBackground(GUI.DISABLED_COLOR_1)
    screen.setForeground(GUI.DISABLED_COLOR_2)
  elseif input.focused then
    screen.setBackground(input.focusColor)
    screen.setForeground(input.focusTextColor)
  else
    screen.setBackground(input.bgColor)
    screen.setForeground(input.textColor)
  end

  -- Background
  screen.drawRect(input.x, input.y, input.width, input.height, input.bgAlpha)

  -- Text is offset from left by 1 and right by 1
  -- The text is limited by the width of the input and will scroll automatically
  local textToRender = input.value

  -- No input value, check if a placeholder is defined --
  if input.placeholder ~= nil and input.placeholderTextColor ~= nil and not input.focused and len(textToRender) == 0 then 
    screen.setForeground(input.placeholderTextColor)
    screen.drawText(input.x + input.pad / 2, input.y + input.height / 2, input.placeholder)
  else
    -- Placeholder always drawn if keep placeholder is true 
    if input.keepPlaceholder then
      local temp = screen.setForeground(input.placeholderTextColor)
      screen.drawText(input.x + input.pad / 2, input.y + input.height / 2, input.placeholder)
      screen.setForeground(temp)
    end

    -- Don't add a space for the cursor if not focused
    local cursorSpace = " "
    if not input.focused then cursorSpace = "" end 

    -- A space will be inserted where the cursor will go
    if input.textMask == nil then
      textToRender = sub(textToRender, 1, input.cursor - 1) .. cursorSpace .. sub(textToRender, input.cursor)
      if len(textToRender) > input.width - input.pad then
        textToRender = sub(textToRender, input.scroll + 1, input.scroll - 2 + input.width)
      end
    else
      textToRender = rep(input.textMask, input.cursor - 1) .. cursorSpace .. rep(input.textMask, len(input.value) - input.cursor)
      if len(textToRender) > input.width - input.pad then
        textToRender = sub(textToRender, input.scroll + 1, input.scroll - 2 + input.width)
      end
    end

    screen.drawText(input.x + input.pad / 2, input.y + input.height / 2, textToRender)

    -- Render the cursor
    if input.focused then
      screen.setForeground(GUI.CURSOR_BLINK)
      screen.drawText(input.x  + input.pad / 2 + input.cursor - input.scroll - 1, input.y + input.height / 2,
        GUI.CURSOR_CHAR)
    end
  end

  -- Debug text
  if input.debug then
    screen.drawText(input.x + GUI.INPUT_LEFT_RIGHT_TOTAL_PAD / 2, input.y + input.height - 1, 
      "C" .. input.cursor .. " S" .. input.scroll .. " LEN" .. len(input.value))
  end
end

function GUI.createInput(x, y, width, height, bgColor, textColor, focusColor, 
    focusTextColor, bgAlpha, placeholderTextColor, placeholder, textMask)
  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, width, "number")
  checkArg(4, height, "number")
  checkArg(5, bgColor, "number")
  checkArg(6, textColor, "number")
  checkArg(7, focusColor, "number")
  checkArg(8, focusTextColor, "number")

  local input = GUIObject:create(x, y, width, height)
  if bgAlpha == nil then bgAlpha = 1 end
  if placeHolderTextColor == nil then placeHolderTextColor = 0x333333 end

  -- Basic Properties --
  input.bgColor = bgColor
  input.textColor = textColor
  input.focusColor = focusColor
  input.focusTextColor = focusTextColor
  input.placeholderTextColor = placeholderTextColor
  input.bgApha = bgAlpha
  input.placeholder = placeholder
  input.textMask = textMask
  input.debug = false

  -- Additional input properties --
  input.type = "input"
  input.eventHandler = inputEventHandler
  input.onInput = nil
  input.onClick = nil
  input.onPaste = nil
  input.onEnter = nil
  input.draw = drawInput
  input.focused = false

  input.nextInput = nil
  input.validate = nil
  input.keepPlaceholder = false

  input.history = false
  input.historyIndex = 1
  input.maxHistorySize = 50
  input.historyArr = {}

  input.scroll = 0
  input.cursor = 1
  input.value = ""

  input.animation = Animation:create(inputAnimation, GUI.CURSOR_BLINK_DURATION, input)
  input.animation:start(math.huge)

  -- Small inputs have no padding
  input.pad = GUI.INPUT_LEFT_RIGHT_TOTAL_PAD
  if input.width == 1 or input.height == 1 then
    input.pad = 0
  end

  return input
end

-- Progress Indicator --
------------------------------------------------
local function drawProgressIndicator(indicator)
  if not indicator.active then screen.setForeground(indicator.bgColor)
  else screen.setForeground(indicator.activeColor2) end
  screen.drawText(indicator.x, indicator.y, rep("▂", indicator.width), 1, true)
end

local function progressIndicatorAnimation(indicator, percentDone, animation)
  indicator.draw(indicator)
  screen.setForeground(indicator.activeColor1)

  if indicator.cycle < indicator.width / 2 then -- No cycling back to beginning
    screen.drawText(indicator.x + indicator.cycle, indicator.y, rep("▂", floor(indicator.width / 2)), 1, true)
  else
    screen.drawText(indicator.x + indicator.cycle, indicator.y, rep("▂", indicator.width - indicator.cycle), 1, true)
    screen.drawText(indicator.x, indicator.y, rep("▂", floor(indicator.width / 2) - indicator.width + indicator.cycle), 1, true)
  end

  indicator.cycle = indicator.cycle + 1
  if indicator.cycle > indicator.width then indicator.cycle = 0 end
  screen.update() -- Fast update cycle requires updating screen
end

function GUI.createProgressIndicator(x, y, bgColor, activeColor1, activeColor2)
  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, bgColor, "number")
  checkArg(4, activeColor1, "number")
  checkArg(5, activeColor2, "number")

  local indicator = GUIObject:create(x, y, GUI.PROGRESS_WIDTH, GUI.PROGRESS_HEIGHT)

  indicator.bgColor = bgColor
  indicator.activeColor1 = activeColor1
  indicator.activeColor2 = activeColor2

  indicator.type = "progress-indicator"
  indicator.draw = drawProgressIndicator

  indicator.cycle = 0
  indicator.animation = Animation:create(progressIndicatorAnimation, GUI.PROGRESS_DELAY, indicator)
  indicator.animation:start(math.huge)
  indicator.active = true

  return indicator
end

-- Progress bar --
------------------------------------------------
local function drawProgressBar(progressbar)
  screen.setForeground(progressbar.color)
  screen.drawText(progressbar.x, progressbar.y, rep("▔", progressbar.width), 1, true)

  screen.setForeground(progressbar.activeColor)
  screen.drawText(progressbar.x, progressbar.y, rep("▔", ceil(progressbar.width * progressbar.value)), 1, true)

  if progressbar.showValue then
    local textToRender = progressbar.prefix 
      .. ceil(progressbar.value * 100) 
      .. progressbar.suffix

    screen.setForeground(progressbar.textColor)
    screen.drawText(progressbar.x + progressbar.width / 2 - len(textToRender) / 2, progressbar.y + 1, textToRender, 1, true)
  end
end

function GUI.createProgressBar(x, y, width, color, activeColor, value, showValue, textColor, prefix, suffix)
  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, width, "number")
  checkArg(4, color, "number")
  checkArg(5, activeColor, "number")
  checkArg(6, value, "number")

  local height = 1
  if showValue then height = 2 end
  local progressbar = GUIObject:create(x, y, width, height)

  progressbar.type = "progressbar"
  progressbar.draw = drawProgressBar
  progressbar.value = value

  progressbar.color = color
  progressbar.activeColor = activeColor
  progressbar.showValue = showValue
  progressbar.textColor = textColor
  progressbar.prefix = prefix or ""
  progressbar.suffix = suffix or ""
  progressbar.setValue = function(val)
    progressbar.value = val
    progressbar:draw()
  end

  return progressbar
end


-- Color Picker (Basic OC palette) --
------------------------------------------------

-- TODO move to func to create new contaner
local colorPickerContainer = GUI.createPanel(55, 8, 65, 25, 0x333333, 1, 1, true)
colorPickerContainer.overrideBound = true

-- Create the color picker grid
do
  local buttonColor

  -- The current square is like a 2D slice of a cube, each dimension
  -- corresponding to H, S, and V (The 2D slice is x = H, y = S) (z / up / down is V)
  for y = 1, 20 do
    for x = 1, 40 do
      buttonColor = color.HSVToHex(x / 40, 1 - y / 20, 1)
      colorPickerContainer.addChild(GUI.createButton(x, y + 1, 1, 1, " ", buttonColor, buttonColor, buttonColor, buttonColor))
    end
  end

  -- Side slider
  for y = 1, 20 do
    buttonColor = color.HSVToHex(1 / 40, 1 - 1/ 20, 1 - y / 20)
    colorPickerContainer.addChild(GUI.createButton(x + 28, y + 1, 2, 1, " ", buttonColor, buttonColor, buttonColor, buttonColor))
  end

  -- Side input values for HSV and RGB
  colorPickerContainer.addChild(GUI.createLabel(47, 2, "R: ", 0x0, 5, 1))
  colorPickerContainer.addChild(GUI.createInput(51, 2, 5, 1, 0x555555, 0xAAAAAA, 0x777777, 0xFFFFFF))

  colorPickerContainer.addChild(GUI.createLabel(47, 4, "G: ", 0x0, 5, 1))
  colorPickerContainer.addChild(GUI.createInput(51, 4, 5, 1, 0x555555, 0xAAAAAA, 0x777777, 0xFFFFFF))

  colorPickerContainer.addChild(GUI.createLabel(47, 6, "B: ", 0x0, 5, 1))
  colorPickerContainer.addChild(GUI.createInput(51, 6, 5, 1, 0x555555, 0xAAAAAA, 0x777777, 0xFFFFFF))

  colorPickerContainer.addChild(GUI.createLabel(47, 9, "H: ", 0x0, 5, 1))
  colorPickerContainer.addChild(GUI.createInput(51, 9, 5, 1, 0x555555, 0xAAAAAA, 0x777777, 0xFFFFFF))

  colorPickerContainer.addChild(GUI.createLabel(47, 11, "S: ", 0x0, 5, 1))
  colorPickerContainer.addChild(GUI.createInput(51, 11, 5, 1, 0x555555, 0xAAAAAA, 0x777777, 0xFFFFFF))

  colorPickerContainer.addChild(GUI.createLabel(47, 13, "V: ", 0x0, 5, 1))
  colorPickerContainer.addChild(GUI.createInput(51, 13, 5, 1, 0x555555, 0xAAAAAA, 0x777777, 0xFFFFFF))

end

local function drawPicker(picker)
  colorPickerContainer.draw(colorPickerContainer)
end

local function pickerEventHandler(picker, ...)
  colorPickerContainer.eventHandler(colorPickerContainer, ...)
end

function GUI.createColorPicker(x, y, width, height, text, currentColor)
  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, width, "number")
  checkArg(4, height, "number")
  checkArg(5, text, "string")
  checkArg(6, currentColor, "number")

  local picker = GUIObject:create(x, y, width, height)

  -- Basic Properties --
  picker.text = text
  picker.currentColor = currentColor

  -- Additional picker properties --
  picker.type = "colorPickerBasic"
  picker.draw = drawPicker
  picker.eventHandler = pickerEventHandler

  return picker
end




-- Terminal --
------------------------------------------------
local function terminalEventHandler(terminal, ...)
  if terminal.disabled then return end -- Ignore event handling for disabled terminals

  local event = select(1, ...)
  if event == "touch" then
    -- Check bounds for touch
    local x, y = select(3, ...), select(4, ...)
    if x < terminal.x or x > terminal.x + terminal.width or
       y < terminal.y or y > terminal.y + terminal.height then
        input.focused = false
        return
    end

    if terminal.onClick then -- Call onclick function
      terminal.onClick(terminal, ...) end
    terminal.focused = true
  elseif event == "key_down" and terminal.focused and terminal.onInput then
    terminal.onInput(terminal, ...)
  elseif event == "clipboard" and terminal.focused and terminal.onPaste then
    terminal.onPaste(terminal, ...)
  end
end

local function drawTerminal(terminal)
  -- TODO FIGURE OUT HOW TO TERMINAL
end

function GUI.createTerminal(x, y, width, height, text, bgColor, textColor, rootDir, bgAlpha)
  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, width, "number")
  checkArg(4, height, "number")
  checkArg(5, text, "string")
  checkArg(6, bgColor, "number")
  checkArg(7, textColor, "number")

  local terminal = GUIObject:create(x, y, width, height)

  if rootDir == nil then rootDir = "/home" end
  if bgAlpha == nil then bgAlpha = 1 end

  -- Basic Properties --
  terminal.bgColor = bgColor
  terminal.textColor = textColor
  terminal.dir = rootDir
  terminal.bgApha = bgAlpha

  -- Additional terminal properties --
  terminal.type = "terminal"
  terminal.eventHandler = terminalEventHandler
  terminal.onInput = nil
  terminal.onClick = nil
  terminal.onPaste = nil
  terminal.draw = drawTerminal
  terminal.focused = false

  return terminal
end

-- Return API
return GUI