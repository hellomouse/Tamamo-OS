local screen = require("screen")
local unicode = require("unicode")
local thread = require("thread")
local color = require("color")
local format = require("format")
local keyboard = require("keyboard")
local component = require("component")
local eventing = require("eventing")
local system -- Due to race condition system cannot be required (yet)

-- Returned object
local GUI = {
  ALIGN_TOP_LEFT = 0,
  ALIGN_TOP_MIDDLE = 1,
  ALIGN_TOP_RIGHT = 2,
  ALIGN_MIDDLE_LEFT = 3,
  ALIGN_MIDDLE_MIDDLE = 4,
  ALIGN_MIDDLE_RIGHT = 5,
  ALIGN_BOTTOM_LEFT = 6,
  ALIGN_BOTTOM_MIDDLE = 7,
  ALIGN_BOTTOM_RIGHT = 8,

  DISABLED_COLOR_1 = 0x5A5A5A,
  DISABLED_COLOR_2 = 0x878787,

  SUCCESS_COLOR = 0x00C853,
  INFO_COLOR = 0x1565C0,
  WARN_COLOR = 0xF57F17,
  ERROR_COLOR = 0xE53935,

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
  PROGRESS_DELAY = 0.05,

  -- Scroll bar
  SCROLL_BAR_FG_COLOR = 0xAAAAAA,
  SCROLL_BAR_BG_COLOR = 0x333333,
  SCROLL_BAR_ERROR_MARGIN = 2,

  -- Syntax Highlighting
  -- Credits to Igor Timofeev's MineOS
  -- https://github.com/IgorTimofeev/MineOS/blob/master/Libraries/GUI.lua
  LUA_SYNTAX_COLOR_SCHEME = {
		codeBackground = 0x1E1E1E,
		text = 0xE1E1E1,
		strings = 0x99FF80,
		loops = 0xFFFF98,
		comments = 0x898989,
		boolean = 0xFFDB40,
		logic = 0xFFCC66,
		numbers = 0x66DBFF,
		functions = 0xFFCC66,
		compares = 0xFFCC66,
		lineNumberBackground = 0x2D2D2D,
		lineNumberColor = 0xC3C3C3,
		scrollBarBackground = 0x2D2D2D,
		scrollBarForeground = 0x5A5A5A,
		selection = 0x4B4B4B,
		indentation = 0x2D2D2D
  },
  
  -- Patterns go under
  -- <string pattern to match> <group color> <shift start index right> <shift end index left>
	LUA_SYNTAX_PATTERNS = {
		"[%.%,%>%<%=%~%+%-%*%/%^%#%%%&]", "compares", 0, 0,
		"[^%a%d][%.%d]+[^%a%d]", "numbers", 1, 1,
		"[^%a%d][%.%d]+$", "numbers", 1, 0,
		"0x%w+", "numbers", 0, 0,
		" not ", "logic", 0, 1,
		" or ", "logic", 0, 1,
		" and ", "logic", 0, 1,
		"function%(", "functions", 0, 1,
		"function%s[^%s%(%)%{%}%[%]]+%(", "functions", 9, 1,
		"nil", "boolean", 0, 0,
		"false", "boolean", 0, 0,
		"true", "boolean", 0, 0,
		" break$", "loops", 0, 0,
		"elseif ", "loops", 0, 1,
		"else[%s%;]", "loops", 0, 1,
		"else$", "loops", 0, 0,
		"function ", "loops", 0, 1,
		"local ", "loops", 0, 1,
		"return", "loops", 0, 0,
		"until ", "loops", 0, 1,
		"then", "loops", 0, 0,
		"if ", "loops", 0, 1,
		"repeat$", "loops", 0, 0,
		" in ", "loops", 0, 1,
		"for ", "loops", 0, 1,
		"end[%s%;]", "loops", 0, 1,
		"end$", "loops", 0, 0,
		"do ", "loops", 0, 1,
		"do$", "loops", 0, 0,
		"while ", "loops", 0, 1,
		"\'[^\']+\'", "strings", 0, 0,
		"\"[^\"]+\"", "strings", 0, 0,
		"%-%-.+", "comments", 0, 0,
	},
}

-- Optimization for lua
local len = unicode.len
local sub = unicode.sub
local char = string.char
local rep = string.rep
local gsub = string.gsub
local find = string.find

local insert = table.insert
local remove = table.remove
local sort = table.sort
local unpack = unpack or table.unpack

local floor = math.floor
local ceil = math.ceil
local min = math.min
local max = math.max
local random = math.random

local drawText = screen.drawText

-- Helper functions
local function isOutside(guiObj, x, y) -- is x, y outside of guiobj bounds
  if x < guiObj.x or x >= guiObj.x + guiObj.width or
     y < guiObj.y or y >= guiObj.y + guiObj.height then
    return true
  end
  return false
end

local function setBackgroundForeground(background, foreground)
  screen.setBackground(background)
  screen.setForeground(foreground)
end

local function drawAlignedText(x, y, width, height, text, align, textWidth, textHeight, color)
    -- 0 = top/left, 1 = middle, 2 = bottom/right
  local ALIGN_X, ALIGN_Y = align % 3, floor(align / 3)
  local textX, textY

  -- Calculate x alignment
  if ALIGN_X == 1 then textX = x + (width - textWidth) / 2   -- Middle
  elseif ALIGN_X == 2 then textX = x + width - textWidth     -- Right
  else textX = x end -- Left

  -- Calculate y alignment
  if ALIGN_Y == 1 then textY = y + (height - textHeight) / 2 -- Middle
  elseif ALIGN_Y == 2 then textY = y + height - textHeight   -- Bottom
  else textY = y end -- Top

  if color then screen.setForeground(color) end
  drawText(textX, textY, text)
end


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



-- Base container class
GUIContainer = {}
GUIContainer.__index = GUIContainer

function GUIContainer:create(x, y, width, height, backgroundColor)
  local obj = {}                  -- New object
  setmetatable(obj, GUIContainer) -- make GUIContainer handle lookup

  obj.x, obj.y, obj.width, obj.height = floor(x), floor(y), floor(width), floor(height)
  obj.backgroundColor = backgroundColor
  obj.children, obj.isChild = {}, false
  obj.type = "GUIContainer"

  obj.skipEventHandler = false
  obj.skipDraw = false
  obj.blockEvents, obj.passEvents = false, false

  -- Optimization settings, do not touch unless you
  -- know what you are doing
  obj.onlyDrawChildOverlap = false
  obj.skipBackgroundRedrawOnChild = false
  obj.skipDrawObjectOnChild = false

  return obj
end

function GUIContainer:findChild(obj)
  for i = 1, #self.children do
    if self.children[i] == obj then return i end
  end
end

local function guiObjectGetPos(guiObject, x, y)
  if x then
    guiObject.localX = x - self.x
    guiObject.x = x
  end
  if y then
    guiObject.localY = y - self.y
    guiObject.y = y
  end
end

function GUIContainer:addChild(guiObject, index)
  -- Add properties
  guiObject.localX = guiObject.x
  guiObject.localY = guiObject.y
  guiObject.parent = self

  -- GUIContainers must have child flag set to true
  if guiObject.type == "GUIContainer" then
    guiObject.isChild = true
  end

  -- Identify the first parent container
  local _tempobj = self
  while _tempobj.parent ~= nil do
    _tempobj = _tempobj.parent
  end

  -- Verify the parent container is not a child element (not added)
  -- and is a GUIContainer
  if not _tempobj.isChild and _tempobj.type == "GUIContainer" then 
    guiObject.firstParent = _tempobj 
  end

  -- Convert local coords to global
  guiObject.x = self.x + guiObject.x
  guiObject.y = self.y + guiObject.y

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
  guiObject.remove = function()
    -- DO NOT remove the isChild property
    guiObject.parent, guiObject.firstParent = nil, nil
    return remove(self.children, self:findChild(guiObject))
  end
  guiObject.setPos = guiObjectGetPos

  if index == nil then insert(self.children, guiObject)
  else insert(self.children, guiObject, index) end
end

function GUIContainer:removeChild(index)
  remove(self.children, index)
end

function GUIContainer:draw(child, offsetX, offsetY) -- Optional child element to update appearance and offset
  -- Skip any drawing updates
  if self.skipDraw then return end 

  -- If child is not nil assert that its parent is self
  if child ~= nil and child.parent ~= self then
    error("Child must be a child of this specific GUI container when passed in :draw()")
  end

  offsetX = offsetX or 0
  offsetY = offsetY or 0

  local seenChild = false -- Child element must render first before overlapping will be considered

  -- If container is a child of another but has no parent then don't render
  if self.isChild and not self.parent then return end

  -- Fill background if parent container or has background
  if (not self.isChild or self.backgroundColor) then
    screen.setBackground(self.backgroundColor or 0x0)
    if child == nil and not (child and self.skipBackgroundRedrawOnChild) then
      screen.drawRectangle(self.x, self.y, self.width, self.height)
    else
      screen.drawRectangle(child.x, child.y, child.width, child.height)
    end
  end

  screen.setDrawingBound(self.x, self.y, self.x + self.width - 1, self.y + self.height - 1)
  self.boundX1, self.boundY1, self.boundX2, self.boundY2 = screen.getDrawingBound()

  -- Custom drawing
  if self.drawObject and not (child and self.skipDrawObjectOnChild) then self:drawObject() end

  for i = 1, #self.children do
    -- Don't render hidden elements
    if self.children[i].hidden then goto continue end
    if self.children[i] == child then seenChild = true end

    -- If only updating child only update elements that overlap with it
    if child == nil or
     (child ~= nil and (seenChild or child.overrideSeenChild) and
      child.x <= self.children[i].x + self.children[i].width and
      child.x + child.width >= self.children[i].x and
      child.y <= self.children[i].y + self.children[i].height and
      child.y + child.height >= self.children[i].y) then -- Do nothing since overlap and valid
    else goto continue end

    -- GUI Containers already set their drawing bounds, otherwise
    -- we need to restrict drawing bounds for them
    if self.children[i].type == "GUIContainer" then
      self.children[i]:draw(nil, offsetX, offsetY)
    else
      self.children[i].x = self.children[i].x + offsetX
      self.children[i].y = self.children[i].y + offsetY

      screen.setDrawingBound(self.children[i].x, self.children[i].y, 
        self.children[i].x + self.children[i].width - 1, self.children[i].y + self.children[i].height - 1, true)
      self.children[i]:drawObject()

      self.children[i].x = self.children[i].x - offsetX
      self.children[i].y = self.children[i].y - offsetY
    end

    screen.setDrawingBound(self.boundX1, self.boundY1, self.boundX2, self.boundY2)
    ::continue::
  end

  -- Some child elements have a drawAfter function
  if child and child.drawAfter then child:drawAfter() end

  -- Avoids flickering with GUIContainers within containers
  if not self.isChild then screen.update() end
end

function GUIContainer:resetBounds()
  screen.setDrawingBound(self.boundX1, self.boundY1, self.boundX2, self.boundY2)
end

function GUIContainer:eventHandler(...)
  if self.skipEventHandler then return end
  for i = #self.children, 1, -1 do -- Process higher z-index first
    if self.children[i] and not self.children[i].disabled and
       self.children[i].eventHandler and not self.children[i].passEvents then
      -- We check if the child should block all events BEFORE
      -- the event handler as the event handler could remove
      -- the child or otherwise alter self.children
      local shouldBlock = self.children[i].blockEvents
      self.children[i]:eventHandler(...)
      if shouldBlock then return end
    end
  end
end

-- Wrapper to create a GUIContainer --
function GUI.createContainer(x, y, width, height, backgroundColor)
  return GUIContainer:create(x, y, width, height, backgroundColor)
end







-- Base GUI Object class
------------------------------------------------
GUIObject = {}
GUIObject.__index = GUIObject

function GUIObject:create(x, y, width, height)
  local obj = {}               -- New object
  setmetatable(obj, GUIObject) -- make GUIObject handle lookup

  x, y, width, height = floor(x), floor(y), floor(width), floor(height)

  obj.x, obj.y, obj.width, obj.height = x, y, width, height
  obj.disabled, obj.hidden = false, false
  obj.overrideSeenChild = false
  obj.type = "GUIObject"
  obj.eventHandler = nil  -- Runs when event is called, override
  obj.blockEvents, obj.passEvents = false, false

  return obj
end

function GUIObject:draw()
  if not self.parent or (self.parent.isChild and not self.firstParent) then return end -- Must have parent container to render
  self.parent:draw(self)
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

  obj.aniFunction, obj.stepSize = aniFunction, stepSize
  obj.GUIObj = GUIObj
  return obj
end

function Animation:start(duration, delay)
  if delay == nil then delay = 0 end
  if self.timer ~= nil then system.detachTimer(self.timer) end

  local i = 0
  self.timer = eventing.Timer:setInterval(function()
    if i > duration then
      system.detachTimer(self.timer)
      self.timer = nil
    end
    
    self.aniFunction(self.GUIObj, i / duration, self)
    i = i + self.stepSize
  end, delay)
  system.attachTimer(self.timer)
end

-- Pause, resume and stop animation
function Animation:pause() system.detachTimer(self.timer) end
function Animation:resume() system.attachTimer(self.timer) end
function Animation:stop(percentDone)
  if percentDone == nil then percentDone = 0 end

  self.aniFunction(self.GUIObj, percentDone) -- Reset animation to initial state
  system.detachTimer(self.timer)
  self.timer = nil
end











------------------------------------------------
-- START GUI SHIT --
------------------------------------------------

-- Panel --
------------------------------------------------
local function drawPanel(panel)
  local bx1, by1, bx2, by2 = screen.getDrawingBound()
  if panel.overrideBound then
    screen.setDrawingBound(panel.x, panel.y, panel.x + panel.width - 1, panel.y + panel.height - 1, false)
  end

  local dx, dy
  if panel.xScrollbar then dx = -panel.xScrollbar.value end
  if panel.yScrollbar then dy = -panel.yScrollbar.value end

  screen.setBackground(panel.color)
  screen.drawRectangle(panel.x, panel.y, panel.width, panel.height, panel.backgroundAlpha)
  panel.container:draw(nil, dx, dy)

  screen.setDrawingBound(panel.x, panel.y, panel.x + panel.width - 1, panel.y + panel.height - 1)

  -- Render any scrollbars it might have
  -- Auto hide scrollbars if scrollX / scrollY is set to "auto" and size < width / height
  if panel.xScrollbar then
    panel.xScrollbar.hidden = scrollX == "auto" and panel.width >= panel.xScrollbar.totalScrollSize
    panel.xScrollbar:drawObject()
  end
  if panel.yScrollbar then
    panel.yScrollbar.hidden = scrollY == "auto" and panel.height >= panel.yScrollbar.totalScrollSize
    panel.yScrollbar:drawObject() 
  end

  -- Reset original bounds
  screen.setDrawingBound(bx1, by1, bx2, by2)
end

local function panelEventHandler(panel, ...)
  panel.container:eventHandler(...)
  if panel.xScrollbar then panel.xScrollbar:eventHandler(...) end
  if panel.yScrollbar then panel.yScrollbar:eventHandler(...) end
end

local function panelAddChild(panel, guiObj, index) panel.container:addChild(guiObj, index) end
local function panelRemoveChild(panel, index) panel.container:removeChild(index) end

function GUI.createPanel(x, y, width, height, backgroundColor, backgroundAlpha, margin,
    overrideBound, scrollX, scrollY, scrollWidth, scrollHeight)
  if backgroundColor == nil then backgroundColor = 1 end
  if margin == nil then margin = 0 end
  checkMultiArg("number", x, y, width, height, backgroundColor, backgroundAlpha, margin)

  local panel = GUIObject:create(x, y, width, height)

  -- Basic Properties --
  panel.color, panel.backgroundAlpha = backgroundColor, backgroundAlpha
  panel.type = "panel"
  panel.drawObject = drawPanel

  -- TODO Assert scrollx / scrolly auto, scrollwidth/height exists when

  -- Scroll bars
  panel.scrollX = scrollX -- true, false or "auto"
  panel.scrollY = scrollY -- true, false or "auto"

  -- Y margin is halved since cells are 2x taller than wide
  panel.container = GUIContainer:create(x + margin, ceil(y + margin / 2), width - margin * 2, height - margin)
  panel.container.isChild = true
  panel.container.parent = panel
  panel.overrideBound = overrideBound

  -- Scroll bars aren't accessible as children elements
  if scrollX then
    local xbar = GUI.createScrollBar(x + 2, y + height, width - 3, false, GUI.SCROLL_BAR_BG_COLOR, GUI.SCROLL_BAR_FG_COLOR)
    xbar.parent, xbar.totalScrollSize = panel, max(scrollWidth, width)
    panel.xScrollbar = xbar
  end
  if scrollY then
    local ybar = GUI.createScrollBar(x + width - 1, y + 2, height - 2, true, GUI.SCROLL_BAR_BG_COLOR, GUI.SCROLL_BAR_FG_COLOR)
    ybar.parent, ybar.totalScrollSize = panel, max(scrollHeight, height)
    panel.yScrollbar = ybar
  end

  -- Functions --
  panel.addChild, panel.removeChild = panelAddChild, panelRemoveChild
  panel.eventHandler = panelEventHandler

  return panel
end

-- Image wrapper --
------------------------------------------------
local function drawImage(img)
  img.loaded:draw(img.x, img.y)
end

function GUI.createImage(x, y, loadedImage)
  checkMultiArg("number", x, y)
  checkArg(3, loadedImage, "table")

  local img = GUIObject:create(x, y, loadedImage.width, loadedImage.height)
  img.type = "image"
  img.drawObject = drawImage
  img.loaded = loadedImage

  return img
end

-- Text Box --
------------------------------------------------
local function drawTextBox(textbox)
  screen.setForeground(textbox.color)

  -- Textbox text should wrap around
  for i = 1, #textbox.lines do
    drawText(textbox.x, textbox.y + i - 1, textbox.lines[i])
  end
end

function GUI.createTextBox(x, y, text, textColor, width, height)
  checkMultiArg("number", x, y)
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

  textbox.align, textbox.color = align, textColor

  -- Additional textbox properties --
  textbox.type = "textbox"
  textbox.drawObject = drawTextBox
  textbox.textWidth, textbox.textHeight = textWidth, textHeight

  return textbox
end

-- Text Labels --
------------------------------------------------
local function drawLabel(label)
  drawAlignedText(label.x, label.y, label.width, label.height, label.text,
    label.align, label.textWidth, label.textHeight, label.color)
end

function GUI.createLabel(x, y, text, textColor, width, height, align)
  checkMultiArg("number", x, y)
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
    height = 1
    textWidth, textHeight = min(width, len(text)), height
  else
    textHeight = 1
    textWidth = len(text)
  end

  local label = GUIObject:create(x, y, width, height)

  -- Basic Properties --
  label.text, label.align, label.color = text, align, textColor

  -- Additional label properties --
  label.type = "label"
  label.drawObject = drawLabel
  label.textWidth = textWidth
  label.textHeight = textHeight

  return label
end

-- Switches --
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
  
  switch:draw() -- Update appearance
end

-- Switch drawing function --
local function drawSwitch(switch)
  screen.setBackground(switch.inactiveColor)
  screen.set(switch.x, switch.y, "     ")

  screen.setBackground(switch.activeColor)
  screen.set(switch.x, switch.y, rep(" ", switch.animationdx))

  screen.setBackground(switch.cursorColor)
  screen.set(switch.x + switch.animationdx, switch.y, "  ")
end

-- Event handler for switch, deals only with touch events for now --
local function switchEventHandler(switch, ...)
  if select(1, ...) == "touch" then
    -- Check bounds for touch
    local x, y = select(3, ...), select(4, ...)
    if isOutside(switch, x, y) then return end

    -- Invert the toggled boolean
    switch.toggled = not switch.toggled
    if switch.onChange then -- Call onchange function
      switch:onChange(...) end
    switch.animation:start(switch.animationDuration)
  end
end

local function switchSetState(switch, state)
  switch.toggled = state
  switch.animation:start(switch.animationDuration)
end

function GUI.createSwitch(x, y, inactiveColor, activeColor, cursorColor)
  checkMultiArg("number", x, y, inactiveColor, activeColor, cursorColor)

  local switch = GUIObject:create(x, y, 5, 1)
  
  -- Basic Properties --
  switch.inactiveColor, switch.activeColor = inactiveColor, activeColor
  switch.cursorColor = cursorColor

  -- Additional switch properties --
  switch.toggled, switch.animationdx, switch.onChange = false, 0, nil
  switch.animationDuration = GUI.BUTTON_ANIMATION_DURATION
  switch.type = "switch"
  switch.eventHandler = switchEventHandler

  switch.drawObject = drawSwitch
  switch.animation = Animation:create(switchAnimation, GUI.BASE_ANIMATION_STEP, switch)
  switch.setState = switchSetState

  return switch
end

-- Checkboxes --
------------------------------------------------
local function drawCheckbox(checkbox)
  setBackgroundForeground(checkbox.toggled and checkbox.activeColor or checkbox.inactiveColor, checkbox.textColor)
  screen.set(checkbox.x, checkbox.y, "  ")
  drawText(checkbox.x + 3, checkbox.y, checkbox.label, 1, true)
end

-- Event handler for checkbox, deals only with touch events for now --
local function checkboxEventHandler(checkbox, ...)
  if select(1, ...) == "touch" then
    -- Check bounds for touch
    local x, y = select(3, ...), select(4, ...)
    if isOutside(checkbox, x, y) then return end

    -- Invert the toggled boolean
    checkbox.toggled = not checkbox.toggled
    if checkbox.onChange then -- Call onchange function
      checkbox:onChange(...) end
    checkbox:draw()
  end
end

local function checkboxSetState(checkbox, state)
  checkbox.toggled = state
  checkbox:draw()
end

function GUI.createCheckbox(x, y, label, inactiveColor, activeColor, textColor)
  checkMultiArg("number", x, y, 1, inactiveColor, activeColor, textColor)
  checkArg(3, label, "string")

  local checkbox = GUIObject:create(x, y, 3 + len(label), 1)
  
  -- Basic Properties --
  checkbox.inactiveColor, checkbox.activeColor = inactiveColor, activeColor
  checkbox.textColor = textColor
  checkbox.label = label
  checkbox.toggled, checkbox.onChange = false, nil

  -- Additional checkbox properties --
  checkbox.type = "checkbox"
  checkbox.eventHandler = checkboxEventHandler
  checkbox.drawObject = drawCheckbox
  checkbox.setState = checkboxSetState

  return checkbox
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

  button:draw() -- Update appearance
end

-- Set the background / foreground colors depending on
-- the button object (isPressed)
local function setButtonColors(button)
  if button.disabled then -- Forcibly override style for disabled buttons
    button.currentColor = GUI.DISABLED_COLOR_1
    button.currentTextColor = GUI.DISABLED_COLOR_2
  end

  setBackgroundForeground(button.currentColor, button.currentTextColor)
end

-- Button drawing function --
local function drawButton(button)
  setButtonColors(button)

  -- Framed buttons do not get the solid fill
  if button.framed then
    screen.drawThinRectangleOutline(button.x, button.y, button.width, button.height, button.bgAlpha)
    drawText(button.x + button.width / 2 - len(button.text) / 2, button.y + button.height / 2, button.text)
  else  
    screen.drawRectangle(button.x, button.y, button.width, button.height, button.bgAlpha)
    screen.set(button.x + button.width / 2 - len(button.text) / 2, button.y + button.height / 2, button.text)
  end
end

-- Event handler for button, deals only with touch events for now --
local function buttonEventHandler(button, etype, ...)
  if etype == "touch" or etype == "walk" then
    -- Check bounds for touch
    local x, y = select(2, ...), select(3, ...)
    if isOutside(button, x, y) then return end

    -- In switch mode, invert the pressed boolean, otherwise
    -- set it equal to true
    if not button.switchMode then button.pressed = true
    else button.pressed = not button.pressed end

    if button.onClick then -- Call onclick function
      button:onClick(...) end

    button.animation:start(button.animationDuration)
  end
end

local function createButton(x, y, width, height, text, buttonColor, textColor, pressedColor, textPressedColor, bgAlpha, isFrame)
  checkMultiArg("number", x, y, width, height, 1, buttonColor, textColor, pressedColor, textPressedColor)
  checkArg(5, text, "string")

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
  button.pressed, button.switchMode, button.onClick = false, false, nil
  button.animationDuration = GUI.BUTTON_ANIMATION_DURATION
  button.type = "button"
  button.eventHandler = buttonEventHandler
  button.drawObject = drawButton
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

-- Slider drawing function --
local function drawSlider(slider)
  slider.value = min(slider.max, max(slider.value, slider.min))

  if slider.showMinMax or slider.showMinMax == nil then
    screen.setForeground(slider.textColor)
    drawText(slider.x, slider.y, slider.minStr)
    drawText(slider.x + slider.width - len(slider.maxStr), slider.y, slider.maxStr)
  end

  -- Render the slider colored bar --
  screen.setForeground(slider.baseColor)
  drawText(slider.x + slider.sliderOffset, slider.y, rep("━", slider.sliderWidth))

  local percentageIn = (slider.value - slider.min) / (slider.max - slider.min)
  if percentageIn == 1 then percentageIn = 0.999 end -- We aren't allowed actually to take up full width due to rendering bug

  screen.setForeground(slider.sliderColor)
  drawText(slider.x + slider.sliderOffset, slider.y, rep("━", ceil(slider.sliderWidth * percentageIn)))
  screen.setForeground(slider.knobColor)
  drawText(slider.x + slider.sliderOffset + floor(slider.sliderWidth * percentageIn), slider.y, "━")

  if slider.showVal then
    local textToDraw = (slider.prefix or "") .. slider.value.. (slider.suffix or "")
    screen.setForeground(slider.textColor)
    drawText(slider.x + slider.width / 2 - len(textToDraw) / 2, slider.y + 1, textToDraw)
  end
end

-- Event handler for slider --
local function sliderEventHandler(slider, etype, ...)
  if etype == "touch" or etype == "drag" then
    -- Check bounds for event
    local x, y = select(2, ...), select(3, ...)
    if isOutside(slider, x, y) then return end

    local oldval = slider.val

    if x <= slider.x + slider.sliderOffset then -- Low bound
      slider.value = slider.min
    elseif x >= slider.x + slider.sliderOffset + slider.sliderWidth - 1 then -- High bound
      slider.value = slider.max
    else
      slider.value = (x - slider.x - slider.sliderOffset) / slider.sliderWidth * (slider.max - slider.min) + slider.min
      slider.value = floor(slider.value / slider.increment) * slider.increment  -- Round to nearest increment
    end

    slider:draw()

    if slider.onChange and oldval ~= slider.val then -- Call onchange function
      slider:onChange(...) end
  end
end

function GUI.createSlider(x, y, width, baseColor, sliderColor, knobColor, textColor, min, max, val, showVal, showMinMax, increment, prefix, suffix)
  -- Variable checking
  checkMultiArg("number", x, y, width, baseColor, sliderColor, knobColor, textColor, min, max, val)
  checkArg(11, showVal, "boolean", "nil")
  checkArg(12, showMinMax, "boolean", "nil")
  checkArg(13, increment, "number", "nil")
  checkArg(14, prefix, "string", "nil")
  checkArg(15, suffix, "string", "nil")

  -- Increment must < min - max + 1 and min < max
  if min >= max then error("min must be less than max (" .. min .. " /< " .. max .. " in GUI.createSlider)") end
  if inc ~= nil and inc > min - max + 1 then error("Increment must be less than the range in GUI.createSlider") end

  -- Create the actual thing
  local height = showVal and 2 or 1
  local slider = GUIObject:create(x, y, width, height)

  -- Basic Properties --
  slider.value = val
  slider.sliderColor, slider.textColor = sliderColor, textColor
  slider.baseColor, slider.knobColor = baseColor, knobColor

  -- Additional slider properties --
  slider.min, slider.max, slider.increment = min, max, increment or 1
  slider.showVal = showVal
  slider.showMinMax = showMinMax
  slider.prefix, slider.suffix = prefix, suffix
  slider.roundNum = false

  slider.type = "slider"
  slider.eventHandler = sliderEventHandler
  slider.onChange = nil
  slider.drawObject = drawSlider

  slider.sliderWidth = slider.width
  slider.sliderOffset = 0

  if showMinMax or showMinMax == nil then
    slider.maxStr = slider.max .. ""
    slider.minStr = slider.min .. ""

    slider.sliderWidth = slider.width - len(slider.minStr) - len(slider.maxStr) - 2
    slider.sliderOffset = len(slider.minStr) + 1
  end

  return slider
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
    if input.onEnter then input:onEnter() end
  elseif code == 15 and input.nextInput then -- Tab
    input.nextInput.focused = true
    input.nextInput:draw()
    input.focused = false
    input:draw()
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
  local event = select(1, ...)
  if event == "touch" then
    -- Check bounds for touch
    local x, y = select(3, ...), select(4, ...)
    if isOutside(input, x, y) then
      if input.focused then
        input.focused = false
        input:draw()
      end
      return
    end

    -- Focus the input and set the cursor
    input.focused = true
    input.cursor = input.scroll + x - input.x - input.pad / 2

    limitCursor(input)

    if input.onClick then -- Call onclick function
      input:onClick(...) end
    input:draw()
  elseif event == "key_down" and input.focused then
    addKeyToInput(input, select(3, ...), select(4, ...))

    if input.onInput then input:onInput(...) end
    input:draw()
  elseif event == "clipboard" and input.focused then -- TODO respect cursor
    if setInputValueTo(
        sub(input.value, 1, input.cursor - 1) .. select(3, ...) .. sub(input.value, input.cursor), input) then
      input.cursor = input.cursor + len(select(3, ...)) -- Move cursor
      input.scroll = input.scroll + len(select(3, ...)) 
      limitCursor(input)
      
      if input.onPaste then input:onPaste(...) end
      input:draw()
    end
  end
end

-- Input cursor animation (Just need to draw)
local function inputAnimation(input, percentDone, animation)
  if input.focused then
    input:draw() -- Update appearance
  end
end

local function drawInput(input)
  -- Color setting
  if input.disabled then -- Forcibly override style for disabled inputs
    setBackgroundForeground(GUI.DISABLED_COLOR_1, GUI.DISABLED_COLOR_2)
  elseif input.focused then
    setBackgroundForeground(input.focusColor, input.focusTextColor)
  else
    setBackgroundForeground(input.bgColor, input.textColor)
  end

  -- Background
  screen.drawRectangle(input.x, input.y, input.width, input.height, input.bgAlpha)

  -- Text is offset from left by 1 and right by 1
  -- The text is limited by the width of the input and will scroll automatically
  local textToRender = input.value

  -- No input value, check if a placeholder is defined --
  if input.placeholder ~= nil and input.placeholderTextColor ~= nil and not input.focused and len(textToRender) == 0 then 
    screen.setForeground(input.placeholderTextColor)
    screen.set(input.x + input.pad / 2, input.y + input.height / 2, input.placeholder)
  else
    -- Placeholder always drawn if keep placeholder is true 
    if input.keepPlaceholder then
      local temp = screen.setForeground(input.placeholderTextColor)
      screen.set(input.x + input.pad / 2, input.y + input.height / 2, input.placeholder)
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

    screen.set(input.x + input.pad / 2, input.y + input.height / 2, textToRender)

    -- Render the cursor
    if input.focused then
      screen.setForeground(GUI.CURSOR_BLINK)
      screen.set(input.x  + input.pad / 2 + input.cursor - input.scroll - 1, input.y + input.height / 2,
        GUI.CURSOR_CHAR)
    end
  end

  -- Debug text
  if input.debug then
    screen.set(input.x + GUI.INPUT_LEFT_RIGHT_TOTAL_PAD / 2, input.y + input.height - 1, 
      "C" .. input.cursor .. " S" .. input.scroll .. " LEN" .. len(input.value))
  end
end

function GUI.createInput(x, y, width, height, bgColor, textColor, focusColor, 
    focusTextColor, bgAlpha, placeholderTextColor, placeholder, textMask)
  checkMultiArg("number", x, y, width, height, bgColor, textColor, focusColor, focusTextColor)

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
  input.drawObject = drawInput
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
  drawText(indicator.x, indicator.y, rep("▂", indicator.width))
  screen.setForeground(indicator.activeColor1)

  if indicator.cycle < indicator.width / 2 then -- No cycling back to beginning
    drawText(indicator.x + indicator.cycle, indicator.y, rep("▂", floor(indicator.width / 2)))
  else
    drawText(indicator.x + indicator.cycle, indicator.y, rep("▂", indicator.width - indicator.cycle))
    drawText(indicator.x, indicator.y, rep("▂", floor(indicator.width / 2) - indicator.width + indicator.cycle))
  end
end

local function progressIndicatorAnimation(indicator, percentDone, animation)
  indicator:draw()
  indicator.cycle = indicator.cycle + 1
  if indicator.cycle > indicator.width then indicator.cycle = 0 end
end

function GUI.createProgressIndicator(x, y, bgColor, activeColor1, activeColor2)
  checkMultiArg("number", x, y, bgColor, activeColor1, activeColor2)

  local indicator = GUIObject:create(x, y, GUI.PROGRESS_WIDTH, GUI.PROGRESS_HEIGHT)

  indicator.bgColor = bgColor
  indicator.activeColor1 = activeColor1
  indicator.activeColor2 = activeColor2

  indicator.type = "progress-indicator"
  indicator.drawObject = drawProgressIndicator

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
  drawText(progressbar.x, progressbar.y, rep("▔", progressbar.width))

  screen.setForeground(progressbar.activeColor)
  drawText(progressbar.x, progressbar.y, rep("▔", ceil(progressbar.width * progressbar.value)))

  if progressbar.showValue then
    local textToRender = progressbar.prefix 
      .. ceil(progressbar.value * 100) 
      .. progressbar.suffix

    screen.setForeground(progressbar.textColor)
    drawText(progressbar.x + progressbar.width / 2 - len(textToRender) / 2, progressbar.y + 1, textToRender)
  end
end

local function progressBarSetValue(progressbar, val)
  progressbar.value = val
  progressbar:draw()
end

function GUI.createProgressBar(x, y, width, color, activeColor, value, showValue, textColor, prefix, suffix)
  checkMultiArg("number", x, y, width, color, activeColor, value)

  local height = showValue and 2 or 1
  local progressbar = GUIObject:create(x, y, width, height)

  progressbar.type = "progressbar"
  progressbar.drawObject = drawProgressBar
  progressbar.value = value

  progressbar.color = color
  progressbar.activeColor = activeColor
  progressbar.showValue = showValue
  progressbar.textColor = textColor
  progressbar.prefix = prefix or ""
  progressbar.suffix = suffix or ""
  progressbar.setValue = progressBarSetValue

  return progressbar
end

-- Scroll bar --
------------------------------------------------
local function drawScrollBar(scrollbar)
  local cursorSize = ceil(scrollbar.size / scrollbar.totalScrollSize * scrollbar.size)
  local scrollRatioLow = floor(scrollbar.value / scrollbar.totalScrollSize * (scrollbar.size - cursorSize))
  local scrollRatioHigh = scrollRatioLow + cursorSize + 1

  if scrollbar.isVertical then
    for i = 1, scrollbar.height do
      if i > scrollRatioLow and i < scrollRatioHigh then screen.setForeground(scrollbar.fgColor)
      else screen.setForeground(scrollbar.bgColor) end
      drawText(scrollbar.x, scrollbar.y + i - 1, "┃")
    end
  else
    screen.setForeground(scrollbar.bgColor)
    drawText(scrollbar.x, scrollbar.y, rep("━", scrollbar.width))

    screen.setForeground(scrollbar.fgColor)
    drawText(scrollbar.x + floor(scrollRatioLow), scrollbar.y, 
      rep("━", cursorSize), 1)
  end
end

-- Event handler for scrollbar --
local function scrollBarEventHandler(scrollbar, etype, ...)
  if etype == "touch" or etype == "drag" then
    -- Allowable error for scrollbar since they are quite thin to click on
    -- Chars are 2x tall as wide so horz. bars need to have half the number of chars margin
    local errorAllowed = GUI.SCROLL_BAR_ERROR_MARGIN
    if not scrollbar.isVertical then errorAllowed = ceil(errorAllowed / 2) end

    -- Check bounds for event
    local x, y = select(2, ...), select(3, ...)
    if x < scrollbar.x - errorAllowed or 
       x > scrollbar.x + scrollbar.width + errorAllowed or
       y < scrollbar.y - errorAllowed or 
       y > scrollbar.y + scrollbar.height + errorAllowed then
        return
    end

    -- New scroll is measured from a range of top to bottom - size
    -- Thus percent in is measured up to a size of the scroll cursor
    -- If horz. then same idea but with x
    local percent
    local cursorSize = floor(scrollbar.size / scrollbar.totalScrollSize * scrollbar.size)
    
    if scrollbar.isVertical then
      percent = (y - scrollbar.y) / (scrollbar.size - cursorSize)
    else percent = (x - scrollbar.x) / (scrollbar.size - cursorSize) end
    
    percent = max(0, min(percent, 1))
    scrollbar.prevValue = scrollbar.value
    scrollbar.value = floor(scrollbar.totalScrollSize * percent)
    scrollbar:draw()
  elseif etype == "scroll" then
    -- Verify scroll key is correct (shift + scroll for horz., scroll for vertical)
    if (keyboard.isShiftDown(component.keyboard.address) and scrollbar.isVertical) or
       (not keyboard.isShiftDown(component.keyboard.address) and not scrollbar.isVertical) 
       then return end

    -- Check if event is in the parent container
    local x, y = select(2, ...), select(3, ...)
    if not scrollbar.parent or isOutside(scrollbar.parent, x, y) then return end
    
    scrollbar.prevValue = scrollbar.value

    local direction = select(5, ...)
    if direction < 0 then -- Scroll up
      scrollbar.value = scrollbar.value + scrollbar.scrollSpeed
    else -- Scroll down
      scrollbar.value = scrollbar.value - scrollbar.scrollSpeed
    end

    -- Force bounds for value
    scrollbar.value = min(scrollbar.totalScrollSize, max(scrollbar.value, 0))
    scrollbar:draw()
  end
end

local function scrollbarSetValue(scrollbar, val)
  scrollbar.prevValue = scrollbar.value
  scrollbar.value = val
  scrollbar:draw()
end

function GUI.createScrollBar(x, y, size, isVertical, bgColor, fgColor)
  checkMultiArg("number", x, y, size, 1, bgColor, fgColor)
  checkArg(4, isVertical, "boolean")
  
  local width, height
  if isVertical then width, height = 1, size
  else width, height = size, 1 end

  local scrollbar = GUIObject:create(x, y, width, height)

  scrollbar.type = "scrollbar"
  scrollbar.drawObject = drawScrollBar
  scrollbar.eventHandler = scrollBarEventHandler
  scrollbar.isVertical = isVertical
  scrollbar.size = size

  scrollbar.bgColor = bgColor
  scrollbar.fgColor = fgColor

  scrollbar.value = 0 -- Scroll offset
  scrollbar.prevValue = 0 -- Previous scroll value
  scrollbar.scrollSpeed = 4
  scrollbar.totalScrollSize = size -- Max scrollable number of chars
 
  scrollbar.setValue = scrollbarSetValue

  return scrollbar
end

-- Chart --
------------------------------------------------
local function formatChartValue(val, round)
  if round <= 0 then return "" .. math.floor(val + 0.5) end -- Round to nearest integer
  return string.format("%." .. round .. "f", val)
end

local function checkIfFillChartValue(cell, chartYValue, chart, y)
  if chart.fillChart then
    return (chartYValue <= cell and 1) or 0
  end

  local nextChartYValue = chart.maxY - ((y - 0.25) / (chart.height - 2)) * (chart.maxY - chart.minY)
  if chartYValue <= cell and nextChartYValue > cell then return 1 end
  return 0
end

local function getSubBrailleChart(y, chart, cell1Max, cell2Max)
  local args, i = {}, 1
  local chartYValue

  for dy = 1, 4 do
    chartYValue = chart.maxY - ((y + dy / 4) / (chart.height - 2)) * (chart.maxY - chart.minY)
    args[i] = checkIfFillChartValue(cell1Max, chartYValue, chart, y + dy / 4)
    args[i + 1] = checkIfFillChartValue(cell2Max, chartYValue, chart, y + dy / 4)
    i = i + 2
  end

  return format.getBrailleChar(unpack(args))
end

local function drawChart(chart)
  -- Clear background
  screen.setBackground(chart.backgroundColor)
  screen.drawRectangle(chart.x, chart.y, chart.width, chart.height)

  -- Search for min / max value for both x and y
  chart.minX, chart.maxX = chart.xValues[1], chart.xValues[#chart.xValues]

  local xOffset = max(
    #formatChartValue(chart.minY, chart.round), 
    #formatChartValue(chart.maxY, chart.round)) + #chart.ySuffix + 1

  -- Render axis (axii?)
  screen.setForeground(chart.axisColor)
  for y = chart.y, chart.y + chart.height - 3 do
    drawText(xOffset + chart.x - 1, y, "┨")
  end
  drawText(chart.x + xOffset, chart.y + chart.height - 2, rep("┯━", (chart.width - xOffset) / 2))
  drawText(chart.x + xOffset - 1, chart.y + chart.height - 2, "┗")

  -- Render axis labels
  local xIncPixel = floor(chart.xSpacing * (chart.width - 2 - xOffset))
  local yIncPixel = floor(chart.ySpacing * (chart.height - 2))

  local xLabel, yLabel
  local xCount, yCount = 0, 0

  for y = chart.y, chart.y + chart.height - 2, yIncPixel do
    yLabel = formatChartValue(chart.maxY - yCount * (chart.maxY - chart.minY), chart.round)
    yCount = yCount + chart.ySpacing

    screen.setForeground(chart.labelColor)
    drawText(chart.x + xOffset - #yLabel - 2, y, yLabel)

    screen.setForeground(chart.labelSuffixColor)
    drawText(chart.x + xOffset - 2, y, chart.ySuffix)

    -- Additional guideline for the chart
    screen.setForeground(0x333333)
    drawText(chart.x + xOffset + 1, y, rep("─", chart.width - xOffset - 3), 1)
  end
  for x = chart.x + xOffset, chart.x + chart.width, xIncPixel do
    xLabel = formatChartValue(chart.minX + xCount * (chart.maxX - chart.minX), chart.round)
    xCount = xCount + chart.xSpacing
    x = x - #xLabel * 0.7 -- 0.7 is arbritrary offset to make sure labels don't go offscreen

    screen.setForeground(chart.labelColor)
    drawText(x, chart.y + chart.height - 1, xLabel)

    screen.setForeground(chart.labelSuffixColor)
    drawText(x + #xLabel, chart.y + chart.height - 1, chart.xSuffix)
  end

  -- Draw the actual chart itself
  screen.setForeground(chart.color)

  local cellBound, cell1Max, cell2Max
  local currentI = 1
  local cellSize = (chart.maxX - chart.minX) / (chart.width - 2 - xOffset) / 2

  for x = 0, chart.width - 2 - xOffset do
    -- Each x value is 2 "cells", which are half a braille character
    -- We iterate all the values between the bounds of each cell, take
    -- the max of each and display it. We also combine overlapping regions
    -- into solid characters since we can't draw pixels, only braille characters
    -- ie:
    -- |      -->     |
    -- ||             []     Where [] is a solid block
    cellBound = cellSize * 2 * x + chart.minX

    -- Max in cell 1
    for i = currentI, #chart.xValues do
      currentI = i
      if chart.xValues[i] < cellBound or chart.xValues[i] > cellBound + cellSize then break end
      if cell1Max == nil or chart.yValues[i] > cell1Max then
        cell1Max = chart.yValues[i]
        currentI = currentI + 1
      end
    end

    -- Max in cell 2
    for i = currentI, #chart.xValues do
      currentI = i
      if chart.xValues[i] < cellBound + cellSize or chart.xValues[i] > cellBound + cellSize * 2 then break end
      if cell2Max == nil or chart.yValues[i] > cell2Max then
        cell2Max = chart.yValues[i]
        currentI = currentI + 1
      end
    end

    cell1Max, cell2Max = cell1Max or -math.huge, cell2Max or -math.huge

    -- Render current cell
    local char
    for y = 0, chart.height - 3 do
      char = getSubBrailleChart(y, chart, cell1Max, cell2Max)
      if char ~= "⠀" then -- Empty braille, not a space
        drawText(x + chart.x + xOffset, y + chart.y, char)
      end
    end

    -- Reset cell1 and cell2
    cell1Max, cell2Max = nil, nil
  end
end

-- Helper function
-- From https://stackoverflow.com/questions/28443085/how-to-sort-two-tables-simultaneously-by-using-one-of-tables-order
local function sort_relative(ref, t, cmp)
  local n = #ref
  assert(#t == n, "List sizes must match in sort_relative")
  local r = {}
  for i = 1, n do r[i] = i end
  if not cmp then cmp = function(a, b) return a < b end end
  sort(r, function(a, b) return cmp(ref[a], ref[b]) end)
  for i = 1, n do r[i] = t[r[i]] end
  return r
end

local function chartUpdate(chart, xValues, yValues)
  sort_relative(xValues, yValues)
  chart.xValues, chart.yValues = xValues, yValues
  chart:draw()
end

local function chartAddPoint(chart, x, y)
  local added = false
  for i = 2, #chart.xValues do
    if x < chart.xValues[i - 1] then
      added = true
      insert(chart.xValues, i - 1, x)
      insert(chart.yValues, i - 1, y)
    end
  end
  if not added then
    chart.xValues[#chart.xValues + 1] = x
    chart.yValues[#chart.yValues + 1] = y
    chart.maxX = x
  end
  chart:draw()
end

local function removePoint(chart, i)
  remove(chart.xValues, i)
  remove(chart.yValues, i)
  if i == 1 then chart.minX = chart.xValues[1] end
  chart:draw()
end

function GUI.createChart(x, y, width, height, axisColor, labelColor, labelSuffixColor, chartColor, backgroundColor, minY, maxY,
    xSpacing, ySpacing, xSuffix, ySuffix, fillChart, xValues, yValues, round)
  checkMultiArg("number", x, y, width, height, axisColor, labelColor, labelSuffixColor, chartColor, backgroundColor, minY, maxY, xSpacing, ySpacing)
  checkArg(12, ySuffix, "string")
  checkArg(13, fillChart, "boolean")
  checkArg(14, xValues, "table")
  checkArg(15, yValues, "table")
  checkArg(16, round, "nil", "number")

  if round == nil then round = 0 end
  if #xValues ~= #yValues then error("Length of x values must equal y values") end
  local chart = GUIObject:create(x, y, width, height)

  chart.type = "chart"
  chart.drawObject = drawChart

  chart.axisColor, chart.labelColor = axisColor, labelColor
  chart.labelSuffixColor, chart.color, chart.backgroundColor = labelSuffixColor, chartColor, backgroundColor
  chart.minY, chart.maxY = minY, maxY
  chart.minX, chart.maxX = nil, nil
  chart.xSpacing, chart.ySpacing = xSpacing, ySpacing
  chart.xSuffix, chart.ySuffix = xSuffix, ySuffix
  chart.fillChart = fillChart

  yValues = sort_relative(xValues, yValues)
  sort(xValues, function(a, b) return a < b end)

  chart.xValues, chart.yValues = xValues, yValues
  chart.round = floor(round)

  chart.update = chartUpdate
  chart.addPoint = chartAddPoint
  chart.removePoint = removePoint

  return chart
end

-- Dropdown --
------------------------------------------------
local function drawDropdown(dropdown)
  dropdown.height = dropdown._seperators + dropdown._size * dropdown.itemHeight + 4 -- 3 for height, 1 for shadow

  -- Top part of the drawing --
  setBackgroundForeground(dropdown.backgroundColor, dropdown.textColor)
  screen.drawRectangle(dropdown.x, dropdown.y, dropdown.width, 3)
  drawText(dropdown.x + 1, dropdown.y + 1, 
    (dropdown.options[dropdown.selected] and dropdown.options[dropdown.selected][4]) or "Select an option...")
  
  setBackgroundForeground(dropdown.arrowBackgroundColor, dropdown.arrowColor)
  screen.drawRectangle(dropdown.x + dropdown.width - 3, dropdown.y, 3, 3)

  if dropdown._toggled then
    drawText(dropdown.x + dropdown.width - 2, dropdown.y + 1, "▲")
  else
    drawText(dropdown.x + dropdown.width - 2, dropdown.y + 1, "▼")
  end
end

local function drawDropdownAfter(dropdown)
  -- Temporarily remove drawing bounds so the dropdown menu can extend
  -- beyond the boundaries of the box
  if dropdown._toggled then
    -- Draw the dropdown options
    local y = dropdown.y + 3

    for i = 1, dropdown._size do
      setBackgroundForeground(dropdown.elementBackgroundColor, dropdown.options[i][3])
      if dropdown.options[i][2] then -- Disabled
        screen.setForeground(GUI.DISABLED_COLOR_2)
      end

      screen.drawRectangle(dropdown.x, y, dropdown.width, dropdown.itemHeight)
      drawText(dropdown.x + 1, y + floor(dropdown.itemHeight / 2), format.trimLength(dropdown.options[i][4], dropdown.width - 2))

      -- Visual seperator
      if dropdown.options[i][6] then
        screen.setForeground(GUI.DISABLED_COLOR_2)
        screen.set(dropdown.x, y + dropdown.itemHeight, rep("─", dropdown.width))
        y = y + 1
      end

      y = y + dropdown.itemHeight
    end

    -- Shadow on the bottom
    screen.setForeground(0x0)
    drawText(dropdown.x, dropdown.y + dropdown.height - 1, rep("▀", dropdown.width), 0.5)
  end
end

local function dropdownEventHandler(dropdown, etype, ...)
  if etype == "touch" or etype == "drag" then
    local x, y = select(2, ...), select(3, ...)

    -- Bound checking
    if x < dropdown.x or x > dropdown.x + dropdown.width or y < dropdown.y then return end
    if y < dropdown.y + 3 then  -- Toggle open / close
      dropdown._toggled = not dropdown._toggled
      dropdown:draw()           -- Clicking on elements
    elseif dropdown._toggled then
      local y1 = dropdown.y + 3

      for i = 1, dropdown._size do
        -- Found a valid selection
        if y >= y1 and y < y1 + dropdown.itemHeight then
          dropdown.selected, dropdown._toggled = i, false
          dropdown:draw()
        end

        if dropdown.options[i][6] then y1 = y1 + 1 end
        y1 = y1 + dropdown.itemHeight
      end
    end
  end
end

local function findDropdownIndex(index, dropdown)
  for i = 1, dropdown._size do
    if dropdown.options[i][1] == index then
      return i
    end
  end
  error("Dropdown does not contain ID " .. index)
end

local function dropdownAddOption(dropdown, id, disabled, color, displayText, onTouch)
  disabled = disabled or false
  color = color or dropdown.textColor
  displayText = displayText or id

  dropdown._size = dropdown._size + 1
  dropdown.options[dropdown._size] = { id, disabled, color, displayText, onTouch }
  dropdown:draw()
end

local function dropdownRemoveOption(dropdown, index)
  if type(index) == "string" then
    index = findDropdownIndex(index, dropdown)
  end
  dropdown._size = dropdown._size - 1
  remove(dropdown.options, index)
  dropdown:draw()
end

local function dropdownAddSeperator(dropdown)
  if dropdown._size == 0 then return end
  dropdown.options[dropdown._size][6] = true
  dropdown._seperators = dropdown._seperators + 1
  dropdown:draw()
end

local function dropdownGetOption(dropdown, index)
  if type(index) == "string" then
    index = findDropdownIndex(index, dropdown)
  end
  return dropdown.options[index]
end

local function dropdownClear(dropdown)
  dropdown.options = {}
  dropdown._size = 0
  dropdown:draw()
end

local function dropdownSize(dropdown)
  return dropdown._size
end

function GUI.createDropdown(x, y, width, itemHeight, backgroundColor, textColor, arrowBackgroundColor, arrowColor, elementBackgroundColor)
  checkMultiArg("number", x, y, width, itemHeight, backgroundColor, textColor, arrowBackgroundColor, arrowColor, elementBackgroundColor)

  local dropdown = GUIObject:create(x, y, width, 3)

  dropdown.type = "dropdown"
  dropdown.drawObject = drawDropdown
  dropdown.drawAfter = drawDropdownAfter
  dropdown.eventHandler = dropdownEventHandler

  dropdown.itemHeight = itemHeight
  dropdown.backgroundColor, dropdown.textColor = backgroundColor, textColor
  dropdown.arrowBackgroundColor, dropdown.arrowColor = arrowBackgroundColor, arrowColor
  dropdown.elementBackgroundColor = elementBackgroundColor
  dropdown.options = {}
  dropdown.selected = 0
  dropdown.overrideSeenChild = true

  dropdown._toggled = false
  dropdown._size = 0
  dropdown._seperators = 0

  dropdown.addOption = dropdownAddOption
  dropdown.removeOption = dropdownRemoveOption
  dropdown.addSeperator = dropdownAddSeperator
  dropdown.getOption = dropdownGetOption
  dropdown.clear = dropdownClear
  dropdown.size = dropdownSize

  return dropdown
end

-- Table --
------------------------------------------------
local function drawTable(GUItable)
  local colWidth, colX, orgFg, colText

  -- Fill background color with row1
  screen.setBackground(GUItable.rowOddBackgroundColor)
  screen.fill(GUItable.x, GUItable.y, GUItable.width, GUItable.height, " ")

  for row = 1, #GUItable.data do
    if row == 1 then -- Header colors --
      setBackgroundForeground(GUItable.headerBackgroundColor, GUItable.headerTextColor)
    elseif (row - 1) % 2 == 0 then -- Even (header doesn't count)
      setBackgroundForeground(GUItable.rowEvenBackgroundColor, GUItable.rowEvenTextColor)
    else -- Odd (header doesn't count)
      setBackgroundForeground(GUItable.rowOddBackgroundColor, GUItable.rowOddTextColor)
    end

    -- Prefill row color
    screen.set(GUItable.x, GUItable.y + row - 1, rep(" ", GUItable.width))

    colX = GUItable.x
    for item = 1, #GUItable.data[row] do
      colWidth = floor((GUItable.colWidths and GUItable.width * GUItable.colWidths[item]) or GUItable.width / #GUItable.data[row])
      colText = format.trimLength(GUItable.data[row][item], colWidth)

      drawAlignedText(colX, GUItable.y + row - 1, colWidth, 1, colText, GUItable.align, len(colText), 1)
      colX = colX + colWidth

      if GUItable.verticalSeperator and item ~= #GUItable.data[row] then
        orgFg = screen.getForeground()
        screen.setForeground(0x0)
        drawText(colX - 1, GUItable.y + row - 1, "│", 0.5)
        screen.setForeground(orgFg)
      end
    end
  end
end

local function tableSetAlign(table, align) table.align = align end

function GUI.createTable(x, y, width, height, data, headerBackgroundColor, headerTextColor,
    rowEvenBackgroundColor, rowEvenTextColor, rowOddBackgroundColor, rowOddTextColor, verticalSeperator, colWidths)
  rowOddBackgroundColor = rowOddBackgroundColor or rowEvenBackgroundColor
  rowOddTextColor = rowOddTextColor or rowEvenTextColor

  checkMultiArg("number", x, y, width, height, 1, headerBackgroundColor, headerTextColor, rowEvenBackgroundColor, rowEvenTextColor,
    rowOddBackgroundColor, rowOddTextColor)
  checkArg(5, data, "table")
  checkArg(12, verticalSeperator, "boolean", "nil")
  checkArg(13, colWidths, "table", "nil")

  local GUItable = GUIObject:create(x, y, width, height)

  GUItable.type = "table"
  GUItable.drawObject = drawTable

  GUItable.data, GUItable.headerBackgroundColor, GUItable.headerTextColor = data, headerBackgroundColor, headerTextColor
  GUItable.rowEvenBackgroundColor, GUItable.rowEvenTextColor = rowEvenBackgroundColor, rowEvenTextColor
  GUItable.rowOddBackgroundColor, GUItable.rowOddTextColor = rowOddBackgroundColor, rowOddTextColor
  GUItable.verticalSeperator, GUItable.colWidths = verticalSeperator, colWidths
  GUItable.align = GUI.ALIGN_MIDDLE_MIDDLE

  GUItable.setAlign = tableSetAlign

  return GUItable
end

-- Code View --
------------------------------------------------
local function drawHighlightedText(line, x, y, syntaxPatterns, colorScheme, indentSize)
  -- Base text (assumed you set base color already)
  drawText(x, y, line)

  -- Indent line
  local indentIndex = 1
  local repStr = rep(" ", indentSize)

  screen.setForeground(colorScheme.indentation)
  while sub(line, indentIndex, indentIndex + indentSize - 1) == repStr do
    screen.set(x + indentIndex - 1, y, "│")
    indentIndex = indentIndex + indentSize
  end

  -- Syntax highlighting for each group
  local index1, index2, group, pattern

  for i = 1, #syntaxPatterns, 4 do
    pattern = syntaxPatterns[i]
    group = syntaxPatterns[i + 1] .. ""

    index1, index2 = find(line, pattern, 1)
    screen.setForeground(colorScheme[group] or 1)

    while index1 ~= nil do
      screen.drawText(x + index1 - 1 + syntaxPatterns[i + 2], y, 
        sub(line, index1 + syntaxPatterns[i + 2], index2 - syntaxPatterns[i + 3]))
      index1, index2 = find(line, pattern, index1 + 1)
    end
  end
end

local function drawCodeView(codeview)
  local dx, dy

  if codeview.scrollable then
    dx = codeview.xScrollbar.value
    dy = max(1, codeview.yScrollbar.value) -- Since dy is start line basically
  else 
    dx = codeview.startCol
    dy = codeview.startLine
  end

  local lineNumberBarWidth = #(dy + codeview.height .. "") + 2
  local maxLineLength = 0
  local currentLineLength, numberToDraw, selectSize

  -- Background
  screen.setBackground(codeview.colorScheme.codeBackground)
  screen.drawRectangle(codeview.x + lineNumberBarWidth, codeview.y, codeview.width - lineNumberBarWidth, codeview.height)

  -- Render text selections
  if codeview.selections then
    local selection
    screen.setBackground(codeview.colorScheme.selection)
    for i = 1, #codeview.selections do
      selection = codeview.selections[i]

      -- Same line selection
      if selection[1] == selection[3] then
        screen.set(codeview.x + selection[2] - dx + lineNumberBarWidth, 
          codeview.y + selection[1] - dy, rep(" ", selection[4] - selection[2] + 1))
      -- Different line selection
      else
        -- Draw first selection rectangle
        screen.set(codeview.x + selection[2] - dx + lineNumberBarWidth,
          codeview.y + selection[1] - dy, rep(" ", len(codeview.lines[selection[1]])))

        -- Middle slection rectangle
        if selection[3] > selection[1] + 1 then
          for line = selection[1] + 1, selection[3] - 1 do
            screen.set(codeview.x + lineNumberBarWidth - dx + 1,
              codeview.y + line - dy, rep(" ", len(codeview.lines[line])))
          end
        end

        -- Last selection rectangle
        screen.set(codeview.x + 1 - dx + lineNumberBarWidth, codeview.y + selection[3] - dy, rep(" ", selection[4] - dx))
      end
    end
    screen.setBackground(codeview.colorScheme.codeBackground)
  end

  -- Render code
  for line = max(1, dy), max(1, dy) + codeview.height - 1 do
    if codeview.lines[line] == nil then goto continue end

    currentLineLength = len(codeview.lines[line])
    if currentLineLength > maxLineLength then
      maxLineLength = currentLineLength
    end

    screen.setForeground(codeview.colorScheme.text)

    -- Highlight the current text
    if codeview.highlights and codeview.highlights[line] then
      selectSize = codeview.width - lineNumberBarWidth
      screen.setBackground(codeview.highlights[line])
      screen.set(codeview.x + lineNumberBarWidth, codeview.y + line - dy, rep(" ", selectSize))
      screen.setBackground(codeview.colorScheme.codeBackground)
    end

    if codeview.syntaxHighlighting then
      drawHighlightedText(codeview.lines[line], codeview.x + lineNumberBarWidth + 1 - dx, 
        codeview.y + line - dy,
        codeview.syntaxPatterns, codeview.colorScheme, codeview.indentSize)
    else
      screen.set(codeview.x + lineNumberBarWidth + 1 - dx, codeview.y + line - dy, codeview.lines[line])
    end

    ::continue::
  end

  -- Update and render scrollbars
  if codeview.scrollable then
    if maxLineLength > codeview.width - lineNumberBarWidth then
      codeview.xScrollbar.width = codeview.width - lineNumberBarWidth
      codeview.xScrollbar.totalScrollSize = maxLineLength - lineNumberBarWidth
      codeview.xScrollbar.x = codeview.x + lineNumberBarWidth
      codeview.xScrollbar:drawObject()
    end
    if #codeview.lines > codeview.height then
      -- Extra rectangle behind to hide any overlapping selections / highlights
      screen.setBackground(codeview.colorScheme.codeBackground)
      screen.drawRectangle(codeview.x + codeview.width - 1, codeview.y, 1, codeview.height)

      codeview.yScrollbar.totalScrollSize = #codeview.lines - codeview.height
      codeview.yScrollbar:drawObject()
    end
  end

  -- Render line numbers
  setBackgroundForeground(codeview.colorScheme.lineNumberBackground, codeview.colorScheme.lineNumberColor)
  screen.drawRectangle(codeview.x, codeview.y, lineNumberBarWidth, codeview.height)

  for n = 1, codeview.height do
    numberToDraw = n + dy - 1

    -- Don't draw the extra 2 padding lines at the end
    if numberToDraw > #codeview.lines - 2 then break end

    numberToDraw = numberToDraw  .. ""
    screen.set(codeview.x + lineNumberBarWidth - 1 - #numberToDraw, codeview.y + n - 1, numberToDraw)
  end
end

local function codeViewEventHandler(codeview, ...)
  if codeview.scrollable then
    codeview.xScrollbar:eventHandler(...)
    codeview.yScrollbar:eventHandler(...)
  end
end

function GUI.createCodeView(x, y, width, height, lines, startLine, startCol, selections, highlights, syntaxPatterns,
    colorScheme, syntaxHighlighting, scrollable, indentSize)
  checkMultiArg("number", x, y, width, height, 1, startLine, startCol)
  checkArg(5, lines, "table")
  checkArg(8, selections, "table", "nil")
  checkArg(9, highlights, "table", "nil")
  checkArg(12, syntaxHighlighting, "boolean")
  checkArg(13, indentSize, "number", "nil")

  if syntaxHighlighting then
    checkArg(10, syntaxPatterns, "table")
    checkArg(11, colorScheme, "table")
    checkArg(12, scrollable, "boolean", "nil")
  end
  if scrollable == nil then scrollable = true end
  if syntaxHighlighting == nil then syntaxHighlighting = true end

  local codeview = GUIObject:create(x, y, width, height)
  codeview.indentSize = indentSize or 2

  -- Correction for windows line breaks and tab chars
  for i = 1, #lines do
    lines[i] = gsub(gsub(lines[i], "\t", rep(" ", codeview.indentSize)), "\r\n", "\n")
  end

  -- Last lines are being cut off due to a scrollbar and startline shift
  -- so we need to increase number of lines (and hence scroll size)
  lines[#lines + 1] = ""
  lines[#lines + 1] = ""

  codeview.type = "codeview"
  codeview.drawObject = drawCodeView
  codeview.eventHandler = codeViewEventHandler
  codeview.scrollable = scrollable

  if scrollable then
    local xbar = GUI.createScrollBar(x + 3, y + height, width - 4, false, colorScheme.scrollBarBackground, colorScheme.scrollBarForeground)
    xbar.parent = codeview
    xbar.totalScrollSize = width
    xbar.value = startCol
    codeview.xScrollbar = xbar

    local ybar = GUI.createScrollBar(x + width, y + 1, height - 1, true, colorScheme.scrollBarBackground, colorScheme.scrollBarForeground)
    ybar.parent = codeview
    ybar.totalScrollSize = height
    ybar.value = startLine
    codeview.yScrollbar = ybar
  end

  codeview.lines = lines
  codeview.startLine = startLine
  codeview.startCol = startCol
  codeview.selections = selections
  codeview.highlights = highlights
  codeview.syntaxPatterns = syntaxPatterns
  codeview.colorScheme = colorScheme
  codeview.syntaxHighlighting = syntaxHighlighting

  return codeview
end

-- List --
------------------------------------------------

local function drawList(list)
  local itemHeight = list.paddingY * 2 + 1
  local x, y = list.x, list.y
  local rectWidth, text

  -- Fill background --
  screen.setBackground(list.backgroundColor)
  screen.drawRectangle(list.x, list.y, list.width, list.height)

  if list.vertical then list.autoSize = false end

  for i = 1, #list.items do
    -- Set colors --
    if list.selected == i then
      setBackgroundForeground(list.backgroundSelectedColor, list.textSelectedColor)
    elseif i % 2 == 1 then
      setBackgroundForeground(list.backgroundColor, list.textColor)
    else
      setBackgroundForeground(list.alternateBackgroundColor, list.alternateTextColor)
    end

    rectWidth = list.autoSize and (len(list.items[i]) + 2 * list.paddingX) or list.itemSize
    text = list.autoSize and list.items[i] or format.trimLength(list.items[i], list.itemSize - 2 * list.paddingX)

    screen.drawRectangle(x, y, rectWidth, itemHeight)
    drawAlignedText(x + list.paddingX, y + list.paddingY,rectWidth - 2 * list.paddingX, itemHeight - 2 * list.paddingY, text, list.align, len(text), 1)

    if list.vertical then y = y + itemHeight + list.spacing
    else x = x + rectWidth + list.spacing end
  end
end

local function listEventHandler(list, etype, ...)
  if etype == "touch" or etype == "drag" then
    local x, y = select(2, ...), select(3, ...)

    -- Bound checking
    if isOutside(list, x, y) then return end

    local itemHeight = list.paddingY * 2 + 1
    local tx, ty = list.x, list.y
    local rectWidth, text

    if list.vertical then list.autoSize = false end

    for i = 1, #list.items do
      rectWidth = list.autoSize and (len(list.items[i]) + 2 * list.paddingX) or list.itemSize

      if x >= tx and x < tx + rectWidth and y >= ty and y < ty + itemHeight then
        if list.onClick then list:onClick(i, ...) end
        list.selected = i
        list:draw()
        return
      end
      
      if list.vertical then ty = ty + itemHeight + list.spacing
      else tx = tx + rectWidth + list.spacing end
    end
  end
end

local function listAddItem(list, item) list.items[#list.items + 1] = item end
local function listGetItem(list, index) return list.items[index] end
local function listSetAlignment(list, align) list.align = align end
local function listGetSpacing(list, spacing) list.spacing = spacing end
local function listGetSpacing(list) return list.spacing end
local function listSetPadding(list, padx, pady)
  list.paddingX, list.paddingY = padx, pady
end
local function getListPadding(list) return list.paddingX, list.paddingY end

function GUI.createList(x, y, width, height, itemSize, spacing, backgroundColor,
    textColor, alternateBackgroundColor, alternateTextColor, backgroundSelectedColor, textSelectedColor, vertical, autoSize)
  checkMultiArg("number", x, y, width, height, itemSize, spacing, backgroundColor, textColor,
   alternateBackgroundColor, alternateTextColor, backgroundSelectedColor, textSelectedColor)
  checkArg(13, vertical, "boolean", "nil")
  checkArg(14, autoWidth, "boolean", "nil")

  local list = GUIObject:create(x, y, width, height)
  
  -- Base properties --
  list.type = "list"
  list.drawObject = drawList
  list.eventHandler = listEventHandler

  -- Additional properties --
  list.itemSize, list.spacing, list.vertical = itemSize, spacing, vertical or false
  list.backgroundColor, list.textColor, list.alternateBackgroundColor,
    list.alternateTextColor, list.backgroundSelectedColor, list.textSelectedColor =
    backgroundColor, textColor, alternateBackgroundColor, alternateTextColor, backgroundSelectedColor, textSelectedColor
  list.autoWidth, list.selected, list.align = autoSize, nil, GUI.ALIGN_MIDDLE_MIDDLE
  list.paddingX, list.paddingY = 1, 1
  list.items = {}

  -- Functions --
  list.addItem = listAddItem
  list.getItem = listGetItem
  list.setAlignment = listSetAlignment
  list.setSpacing = listSetSpacing
  list.getSpacing = listGetSpacing
  list.setPadding = listSetPadding
  list.getPadding = listGetPadding

  -- Overrideable functions --
  list.onClick = nil
  
  return list
end




-- Color Picker Container --
------------------------------------------------
local colorPickerContainer
local colorPickerColor, colorPickerPrevColor = 0xFF0000, 0xFF0000
local colorPickerX, colorPickerY, colorPickerV, colorPickerSaved = 1, 1, 1, {}
local colorPickerMaxSaveSize = 6

local function createColorPicker()
  colorPickerContainer = GUI.createContainer(screen.getWidth() / 2 - 65 / 2, screen.getHeight() / 2 - 25 / 2, 66, 25, 0x222222)
  local colorPickerInputLeftX = 52
  local colorPickerInputTopY = 5

  local colorSelectorPartWidth = 45
  local colorSelectorPartHeight = 25
  local brightnessBarHeight = 21

  -- Optimization --
  colorPickerContainer.skipBackgroundRedrawOnChild = true
  colorPickerContainer.skipDrawObjectOnChild = true

  -- Create the color picker grid
  colorPickerContainer.drawObject = function(container)
    -- The current square is like a 2D slice of a cube, each dimension
    -- corresponding to H, S, and V (The 2D slice is x = H, y = S) (z / up / down is V)
    screen.setForeground(colorPickerV > 0.5 and 0x0 or 0xFFFFFF)

    for y = 1, colorSelectorPartHeight do
      for x = 1, colorSelectorPartWidth do
        screen.setBackground(color.HSVToHex(x / colorSelectorPartWidth, 1 - y / colorSelectorPartHeight, colorPickerV))
        screen.set(container.x + x - 1, container.y + y - 1, (x == colorPickerX and y == colorPickerY and "□") or " ")
      end
    end

    -- Side slider for brightness --
    for y = 1, brightnessBarHeight do
      screen.setBackground(color.HSVToHex(colorPickerX / colorSelectorPartWidth, 1 - colorPickerY / colorSelectorPartHeight, 1 - y / brightnessBarHeight))
      screen.set(container.x + 47, container.y + y, "  ")
    end

    -- Arrow for side slider --
    screen.setForeground(0xFFFFFF)
    drawText(container.x + 49, container.y + 1 + (brightnessBarHeight - 1) * (1 - colorPickerV), "<")

    -- Top values for "current" and "previous" colors --
    screen.setBackground(colorPickerColor)
    screen.drawRectangle(container.x + colorPickerInputLeftX, container.y + 1, 6, 3)
    screen.setBackground(colorPickerPrevColor)
    screen.drawRectangle(container.x + colorPickerInputLeftX + 6, container.y + 1, 6, 3)

    -- Currently saved colors --
    for i = 1, #colorPickerSaved do
      screen.setBackground(colorPickerSaved[i])
      screen.set(container.x + container.width - 16 + i * 2, container.y + container.height - 6, "  ")
    end
  end

  -- Inputs --
  local function makeRGBHSVInput(dy)
    return GUI.createInput(colorPickerInputLeftX + 4, colorPickerInputTopY + dy, 8, 1, 0x555555, 0xAAAAAA, 0x777777, 0xFFFFFF)
  end

  local rinput = makeRGBHSVInput(0)
  local ginput = makeRGBHSVInput(2)
  local binput = makeRGBHSVInput(4)
  local hinput = makeRGBHSVInput(6)
  local sinput = makeRGBHSVInput(8)
  local vinput = makeRGBHSVInput(10)
  local colorinput = GUI.createInput(colorPickerInputLeftX + 2, colorPickerInputTopY + 12, 10, 1, 0x555555, 0xAAAAAA, 0x777777, 0xFFFFFF)

  -- Event handler for container --
  local oldEventHandler = colorPickerContainer.eventHandler

  local function updateRGBInputs()
    local r,g,b = color.HexToRGB(colorPickerColor)
    rinput.value, ginput.value, binput.value = r .. "", g .. "", b .. ""
  end
  local function updateHSVInputs()
    hinput.value, sinput.value, vinput.value = 
      floor(colorPickerX / colorSelectorPartWidth * 100 + 0.5) .. "",
      floor((1 - colorPickerY / colorSelectorPartHeight) * 100 + 0.5) .. "",
      floor(colorPickerV * 100 + 0.5) .. ""
  end
  local function updateRGBHSVInputs()
    updateRGBInputs()
    updateHSVInputs()
  end
  local function updateXYV()
    colorPickerX, colorPickerY, colorPickerV = color.HexToHSV(colorPickerColor)
    colorPickerX, colorPickerY = floor(colorSelectorPartWidth * colorPickerX + 1),
                                floor(colorSelectorPartHeight * (1 - colorPickerY) + 1)
  end
  local function updateHex()
    colorinput.value = string.format("%x", colorPickerColor)
  end
  local function calculateNewColors(method)
    -- There are 3 methods to updating:
    -- (default: 0 or nil)      - Updates all input values
    -- (updating rgb: 1)        - Updates hex input and x/y value and hsv input
    -- (updating hsv: 2)        - Updates hex input and x/y value and rgb input
    -- (updating hex value: 3)  - Update rgb + hsv input and x/y value
    -- (updating directly: 4)   - Update everything

    if not method then
      colorPickerColor = color.HSVToHex(colorPickerX / colorSelectorPartWidth, 1 - colorPickerY / colorSelectorPartHeight, colorPickerV)
      updateRGBHSVInputs()
      updateHex()
    elseif method == 1 then
      if #rinput.value == 0 or #ginput.value == 0 or #binput.value == 0 then return end -- Validation
      colorPickerColor = color.RGBToHex(tonumber(rinput.value), tonumber(ginput.value), tonumber(binput.value))
      updateHSVInputs()
      updateXYV()
      updateHex()
    elseif method == 2 then
      if #hinput.value == 0 or #sinput.value == 0 or #vinput.value == 0 then return end -- Validation
      colorPickerColor = color.HSVToHex(tonumber(hinput.value) / 100, tonumber(sinput.value) / 100, tonumber(vinput.value) / 100)
      updateRGBInputs()
      updateXYV()
      updateHex()
    elseif method == 3 then
      if #colorinput.value == 0 then return end -- Validation
      colorPickerColor = tonumber(colorinput.value, 16)
      updateRGBHSVInputs()
      updateXYV()
    elseif method == 4 then
      updateXYV()
      updateRGBHSVInputs()
      updateHex()
    end

    -- Redraw on these events (input might be updated)
    -- We must manually specify to draw as skipDrawObjectOnChild is true
    -- for optimization purposes, meaning that the color slider and map
    -- won't update on one of its children GUI objects calling :draw()
    colorPickerContainer:draw()
  end

  colorPickerContainer.calculateNewColors = calculateNewColors -- Needed outside of colorPickerContainer

  -- On input updates
  colorinput.onInput = function() calculateNewColors(3) end
  rinput.onInput = function() calculateNewColors(1) end
  ginput.onInput, binput.onInput = rinput.onInput, rinput.onInput
  hinput.onInput = function() calculateNewColors(2) end
  sinput.onInput, vinput.onInput = hinput.onInput, hinput.onInput

  -- Input validation
  colorinput.validate = function(val)
    if len(val) > 6 then return false end
    return tonumber(val, 16) ~= nil
  end
  local function validateRGB(val)
    local n = tonumber(val)
    return n ~= nil and n >= 0 and n <= 255
  end
  rinput.validate, ginput.validate, binput.validate = validateRGB, validateRGB, validateRGB
  local function validateHSV(val)
    local n = tonumber(val)
    return n ~= nil and n >= 0 and n <= 100
  end
  hinput.validate, sinput.validate, vinput.validate = validateHSV, validateHSV, validateHSV
    
  colorPickerContainer.eventHandler = function(container, etype, ...)
    -- Click event for selecting brightess or color --
    if etype == "touch" or etype == "drag" then
      local x, y = select(2, ...) - container.x + 1, select(3, ...) - container.y + 1
      x, y = max(x, 1), max(min(y, colorSelectorPartHeight), 1)
      if x <= colorSelectorPartWidth then -- Left part
        colorPickerX, colorPickerY = x, y
        calculateNewColors()              -- Brightness slider
      elseif x >= colorSelectorPartWidth + 2 and x < colorSelectorPartWidth + 5 and
             y >= 1 and y < brightnessBarHeight + 2 then
        colorPickerV = 1 - (y - 1) / brightnessBarHeight
        calculateNewColors()
      elseif x >= container.width - 16 and x <= container.width - 14 + colorPickerMaxSaveSize * 2 and
             y >= container.height - 5 and y < container.height - 4 then
        local index = floor((x - (container.width - 15)) / 2)
        if colorPickerSaved[index] ~= nil then
          colorPickerColor = colorPickerSaved[index]
          calculateNewColors(4)
        end
      end
    end

    oldEventHandler(container, etype, ...)
  end

  -- Side input values for HSV and RGB
  local function makeRGBHSVLabel(dy, text, noColon)
    return GUI.createLabel(colorPickerInputLeftX, colorPickerInputTopY + dy, text .. (not noColon and ": " or ""), 0xFFFFFF, 5, 1)
  end

  local labelNames = {"R", "G", "B", "H", "S", "V"}
  local inputsToAdd = {rinput, ginput, binput, hinput, sinput, vinput}
  for i = 1, #labelNames do
    colorPickerContainer:addChild(makeRGBHSVLabel((i - 1) * 2, labelNames[i]))
    colorPickerContainer:addChild(inputsToAdd[i])
  end

  colorPickerContainer:addChild(makeRGBHSVLabel(12, "#", true))
  colorPickerContainer:addChild(colorinput)

  -- Ok and cancel button --
  colorPickerContainer.OKButton = GUI.createButton(colorPickerInputLeftX + 4, colorPickerContainer.height - 2, 9, 1, "OK", GUI.DISABLED_COLOR_1, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF)
  colorPickerContainer.CancelButton = GUI.createButton(colorPickerInputLeftX - 6, colorPickerContainer.height - 2, 9, 1, "Cancel", GUI.DISABLED_COLOR_1, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF)
  colorPickerContainer:addChild(colorPickerContainer.OKButton)
  colorPickerContainer:addChild(colorPickerContainer.CancelButton)

  -- Current colors button --
  local addNewColorButton = GUI.createButton(colorPickerContainer.width - 14, colorPickerContainer.height - 5, 12, 1, "+", GUI.DISABLED_COLOR_1, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF)
  addNewColorButton.onClick = function(button)
    if #colorPickerSaved < colorPickerMaxSaveSize then
      colorPickerSaved[#colorPickerSaved + 1] = colorPickerColor
    else
      for i = 2, colorPickerMaxSaveSize do colorPickerSaved[i - 1] = colorPickerSaved[i] end
      colorPickerSaved[colorPickerMaxSaveSize] = colorPickerColor
    end
    colorPickerContainer:draw()
  end
  colorPickerContainer:addChild(addNewColorButton)

  -- Pregen the input values --
  calculateNewColors(4)
end


function GUI.test()
  return colorPickerContainer
end


-- Color Picker (GUI object) --
------------------------------------------------
local function drawPicker(picker)
  screen.setBackground(picker.currentColor)
  screen.drawRectangle(picker.x, picker.y, picker.width, picker.height)

  -- Shadow on the bottom (If enough room) --
  if picker.height > 1 then
    screen.setBackground(0x0)
    screen.drawBrailleRectangle(picker.x, picker.y + picker.height - 0.5, picker.width, 0.5, 0.5)
  end

  screen.setForeground(colorPickerV > 0.5 and 0x0 or 0xFFFFFF)
  screen.drawText(picker.x + 1, picker.y + picker.height / 2, format.trimLength(picker.text, picker.width - 2))
end

local function pickerEventHandler(picker, etype, ...)
  if etype == "touch" or etype == "drag" then
    local x, y = select(2, ...), select(3, ...)
    if isOutside(picker, x, y) then return end

    screen.clear(0x0, 0.5) -- Darken background
    screen.setBackground(0x0) -- Drop shadow
    screen.drawBrailleRectangle(colorPickerContainer.x, colorPickerContainer.y + colorPickerContainer.height, colorPickerContainer.width, 0.5)
    local close = system.addSystemOverlay(colorPickerContainer) -- Show picker

    -- Set color picker color to current selected --
    colorPickerColor, colorPickerPrevColor = picker.currentColor, picker.currentColor
    colorPickerContainer.calculateNewColors(4)

    colorPickerContainer.OKButton.onClick = function()
      picker.currentColor = colorPickerColor
      if picker.onSelection then picker:onSelection(colorPickerColor) end
      close()
    end
    colorPickerContainer.CancelButton.onClick = close
  end
end

function GUI.createColorPicker(x, y, width, height, text, currentColor)
  checkMultiArg("number", x, y, width, height)
  checkArg(5, text, "string")
  checkArg(6, currentColor, "number")

  local picker = GUIObject:create(x, y, width, height)

  -- Basic Properties --
  picker.text = text
  picker.currentColor = currentColor

  -- Additional picker properties --
  picker.type = "colorpicker"
  picker.drawObject = drawPicker
  picker.eventHandler = pickerEventHandler

  -- Configurable properties --
  picker.onSelection = nil
  return picker
end






-- Loading in for system --
function GUI.loadSystem(sys)
  if system then return end
  system = sys

  -- Create dialog popup containers --
  createColorPicker()
end

-- Return API
return GUI