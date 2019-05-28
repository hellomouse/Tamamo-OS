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

  CURSOR_CHAR = " ",         -- This value changes back and forth
  CURSOR_BLINK = 0x0FFAA00, 
  CURSOR_BLINK_DURATION = 0.5,
}

-- Optimization for lua
local len = unicode.len
local sub = unicode.sub
local char = string.char
local rep = string.rep

local insert = table.insert
local remove = table.remove

local floor = math.floor
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

function GUIContainer:addChild(guiObject, index)
  -- TODO convert global coords to local
  -- TODO margins for containers? or have a panel class?

  if index == nil then 
    insert(self.children, guiObject)
  else
    insert(self.children, guiObject, index)
  end
end

function GUIContainer:draw()
  -- TODO scrollbars and shit
  screen.setDrawingBound(self.x, self.y, self.x + self.width - 1, self.y + self.height - 1, true)
  local bx1, by1, bx2, by2 = screen.getDrawingBound()

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

    screen.setDrawingBound(bx1, by1, bx2, by2)
    ::continue::
  end
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


-- Colored Panels --
------------------------------------------------
local function drawPanel(panel)
  screen.setBackground(panel.color)
  screen.drawRect(panel.x, panel.y, panel.width, panel.height, panel.alpha)
end

function GUI.createPanel(x, y, width, height, color, alpha)
  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, width, "number")
  checkArg(4, height, "number")
  checkArg(5, color, "number")

  if not alpha then alpha = 1 end

  local panel = GUIObject:create(x, y, width, height)
  panel.color = color
  panel.type = "panel"
  panel.draw = drawPanel
  panel.alpha = alpha

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
    input.value = input.historyArr[input.historyIndex]
    input.scroll = 0
    input.cursor = len(input.value) + 1

  elseif code == 208 and input.history then -- Down arrow 
    input.historyIndex = input.historyIndex + 1
    if input.historyIndex > #input.historyArr then input.historyIndex = 1 end
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
    input.cursor = input.scroll + x - input.x - GUI.INPUT_LEFT_RIGHT_TOTAL_PAD / 2
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
    screen.drawText(input.x + GUI.INPUT_LEFT_RIGHT_TOTAL_PAD / 2, input.y + input.height / 2, input.placeholder)
  else
    -- Placeholder always drawn if keep placeholder is true 
    if input.keepPlaceholder then
      local temp = screen.setForeground(input.placeholderTextColor)
      screen.drawText(input.x + GUI.INPUT_LEFT_RIGHT_TOTAL_PAD / 2, input.y + input.height / 2, input.placeholder)
      screen.setForeground(temp)
    end

    -- Don't add a space for the cursor if not focused
    local cursorSpace = " "
    if not input.focused then cursorSpace = "" end 

    -- A space will be inserted where the cursor will go
    if input.textMask == nil then
      textToRender = sub(textToRender, 1, input.cursor - 1) .. cursorSpace .. sub(textToRender, input.cursor)
      if len(textToRender) > input.width - GUI.INPUT_LEFT_RIGHT_TOTAL_PAD then
        textToRender = sub(textToRender, input.scroll + 1, input.scroll - 2 + input.width)
      end
    else
      textToRender = rep(input.textMask, input.cursor - 1) .. cursorSpace .. rep(input.textMask, len(input.value) - input.cursor)
      if len(textToRender) > input.width - GUI.INPUT_LEFT_RIGHT_TOTAL_PAD then
        textToRender = sub(textToRender, input.scroll + 1, input.scroll - 2 + input.width)
      end
    end

    screen.drawText(input.x + GUI.INPUT_LEFT_RIGHT_TOTAL_PAD / 2, input.y + input.height / 2, textToRender)

    -- Render the cursor
    if input.focused then
      screen.setForeground(GUI.CURSOR_BLINK)
      screen.drawText(input.x  + GUI.INPUT_LEFT_RIGHT_TOTAL_PAD / 2 + input.cursor - input.scroll - 1, input.y + input.height / 2,
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

  return input
end


-- Color Picker --
------------------------------------------------
local function drawPicker(picker)
  
end

function GUI.createColorPicker(x, y, text, textColor, width, height, align)
  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, text, "string")
  checkArg(4, textColor, "number")

  local label = GUIObject:create(x, y, width, height)

  -- Basic Properties --
  label.text = text
  label.align = align
  label.color = textColor

  -- Additional label properties --
  label.type = "label"
  label.draw = drawLabel

  return label
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