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
}

-- Optimization for lua
local len = unicode.len
local insert = table.insert
local floor = math.floor
local min = math.min


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

    self.children[i].draw(self.children[i])

    -- We need to properly reset drawing bounds if the child element
    -- was a GUI container
    if self.children[i].type == "GUIContainer" then
      screen.setDrawingBound(bx1, by1, bx2, by2)
    end

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
  button.onTouch = nil
  button.type = "button"
  button.eventHandler = buttonEventHandler
  button.onClick = onClick
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

-- Return API
return GUI