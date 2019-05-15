local screen = require("screen")
local unicode = require("unicode")

-- Returned object
local GUI = {}

-- Optimization for lua
local len = unicode.len
local insert = table.insert

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
  obj.children = {}
  return obj
end

function GUIContainer:addChild(guiObject, index)
  -- TODO convert global coords to local

  insert(self.children, guiObject, index)
end

function GUIContainer:draw()
  -- TODO scrollbars and shit

  for i = 1, #self.children do
    -- Don't render hidden elements
    if self.children[i].hidden then goto continue end

    self.children[i].draw(self.children[i])
    ::continue::
  end
end

-- Base GUI Object class
GUIObject = {}
GUIObject.__index = GUIObject

function GUIObject:create(x, y, width, height)
  local obj = {}               -- New object
  setmetatable(obj, GUIObject) -- make GUIObject handle lookup

  obj.x, obj.y, obj.width, obj.height = x, y, width, height
  obj.disabled, obj.hidden = false, false
  return obj
end

-- Buttons
local function setButtonColors(button, isFramed)
  if button.pressed then
    screen.setBackground(button.pressedColor)
    screen.setForeground(button.textPressedColor)
  else
    screen.setBackground(button.buttonColor)
    screen.setForeground(button.textColor)
  end
end

local function drawButtonDefault(button)
  setButtonColors(button)
  screen.drawRect(button.x, button.y, button.width, button.height, button.bgAlpha)
  screen.drawText(button.x + button.width / 2 - len(button.text) / 2, button.y + button.height / 2,
    button.text)
end

local function drawButtonFramed(button)
  setButtonColors(button)
  screen.drawRectOutline(button.x, button.y, button.width, button.height, button.bgAlpha)
  screen.drawText(button.x + button.width / 2 - len(button.text) / 2, button.y + button.height / 2,
    button.text, false, true)
end

local function createButton(x, y, width, height, text, buttonColor, textColor, pressedColor, textPressedColor, bgAlpha, isFrame)
  local button = GUIObject:create(x, y, width, height)

  if bgAlpha == nil then bgAlpha = 1 end
  
  -- Basic Properties --
  button.text = text
  button.buttonColor, button.textColor = buttonColor, textColor
  button.pressedColor, button.textPressedColor = pressedColor, textPressedColor
  button.bgAlpha = bgAlpha

  -- Additional button properties --
  button.pressed = false
  button.switchMode = false
  button.animationDuration = 0.2
  button.onTouch = nil
  if isFrame then button.draw = drawButtonFramed
  else button.draw = drawButtonDefault end

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