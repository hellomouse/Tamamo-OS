-- Double Buffered Magic --
local component = require("component")
local unicode = require("unicode")
local color = require("color")

local gpu = component.gpu

-- Buffer which stores all the changes
-- that are to be displayed on the screen
local buffWidth, buffHeight
local buffBg, buffFg, buffSym
local changeBg, changeFg, changeSym

local buffCurrent, buffChange

-- Limits for drawing on the buffer, to avoid 
-- checking for excessive changes
local drawX1, drawY1, drawX2, drawY2 = 0, 0, buffWidth, buffHeight

-- Current fg / bg colors for set and fill
local currentBg, currentFg = 0, 0xFFFFFF

-- Optimization for lua / gpu proxying
local gpuProxy, GPUfill, GPUset, GPUsetBackground, GPUsetForeground
local GPUgetResolution, GPUsetResolution, GPUgetPaletteColor, GPUcopy, GPUsetResolution
local GPUgetBackground, GPUgetForeground

local rep = string.rep
local sub = unicode.sub
local floor = math.floor
local len = unicode.len

-- Local functions to modify and get data from current buffers
local function getBuff(buff, index)
  c1, rest = buff[index]:match("([^,]+),([^,]+)")
  return tonumber(c1), tonumber(sub(rest, 1, len(rest) - 1)), sub(rest, len(rest))
end

local function setBuff(buff, index, c1, c2, symbol)
  buff[index] = tostring(c1) .. "," .. tostring(c2) .. symbol
end


-- Constants
local fillIfAreaIsGreaterThan = 40
local setToFillRatio = 2 -- Ratio of max set() calls / fill() calls per tick, defined in card

-- Convert x y coords to a buffer index
local function getIndex(x, y)
	return buffWidth * (y - 1) + x
end

-- Check if two characters at the buffers are
-- equal. Equality is checked by symbol, fg and bg
-- unless the character is whitespace, in which case
-- fg is ignored
local function areEqual(sym, changesym, bg, changebg, fg, changefg)
  -- If symbols don't match or backgrounds match always unequal
  if sym ~= changesym or bg ~= changebg then return false end
  if sym == " " or sym == "⠀" then return true end -- 2nd is unicode 0x2800, not regular space
  return fg == changefg
end

-- Same as areEqual but accepts 2 indexes for the respective buffers
local function areEqualIndex(index1, index2)
  local bg1, fg1, sym1 = getBuff(buffChange, index1)
  local bg2, fg2, sym2 = getBuff(buffCurrent, index2)
  return areEqual(sym1, sym2, bg1, bg2, fg1, fg2)
end

-- Palette index = (-index - 1), this takes the "absolute"
-- value to convert to the proper index if negative
local function absColor(val) 
  if val < 0 then return -val - 1 end
  return val
end 

-- Normalize a color to a 24 bit int (Including)
-- palette indexes
local function normalizeColor(val)
  if val < 0 then return GPUgetPaletteColor(-val - 1) end
  return val
end

--------------------------------------------------------

-- Set GPU Proxy for the screen --
function setGPUProxy(gpu)
  -- Define local variables
  gpuProxy = gpu
  GPUfill, GPUset, GPUcopy = gpu.fill, gpu.set, gpu.copy
  GPUsetBackground, GPUsetForeground = gpu.setBackground, gpu.setForeground
  GPUgetBackground, GPUgetForeground = gpu.getBackground, gpu.getForeground
  GPUgetResolution, GPUsetResolution = gpu.getResolution, gpu.setResolution
  GPUgetPaletteColor = gpu.getPaletteColor

  -- Override GPU API
  gpu.set, gpu.copy, gpu.fill = set, copy, fill
  gpu.setBackground, gpu.setForeground = setBackground, setForeground
  gpu.getBackground, gpu.getForeground = getBackground, getForeground
  gpu.setResolution, gpu.getResolution = setResolution, getResolution

  -- Prefill buffer
  flush()
end

-- Get GPU Proxy for the screen --
function getGPUProxy()
  return gpuProxy
end

-- Bind the gpu proxy to a screen address --
function bind(screenAddress, reset)
  local success, reason = gpuProxy.bind(address, reset)
	if success then
		if reset then setResolution(gpuProxy.maxResolution())
    else setResolution(bufferWidth, bufferHeight) end
  end
  return success, reason
end

-- Flush the buffer and re-create each array --
function flush(w, h)
  if w == nil or h == nil then
    w, h = GPUgetResolution()
  end
  buffWidth = w
  buffHeight = h

  drawX1, drawX2 = w, 0
  drawY1, drawY2 = h, 0

  buffCurrent = {}
  buffChange = {}

  -- Prefill the buffers to avoid rehashing (-17 is transparent) --
  for i = 1, w * h do
    buffCurrent[i] = "0,0 "
    buffChange[i] = "-17,-17, "
  end
end

-- Clear the screen by filling with black whitespace chars --
function clear(color)
  setBackground(color)
  fill(0, 0, buffWidth, buffHeight, " ")

  drawX1, drawX2 = w, 0
  drawY1, drawY2 = h, 0
end

-- Set a specific character (internal method) --
function setChar(x, y, fgColor, bgColor, symbol, isPalette1, isPalette2)
  if x < 1 or y < 1 or x > buffWidth or y > buffHeight then return false end
  if len(symbol) ~= 1 then return false end
  local i = getIndex(x, y)

  -- Update draw bounds if needed
  if x < drawX1 then drawX1 = x end
  if x > drawX2 then drawX2 = x end
  if y < drawY1 then drawY1 = y end
  if y > drawY2 then drawY2 = y end

  -- We'll represent palette indexes with negative numbers - 1
  -- ie palette index 3 is saved as -4
  if isPalette1 then fgColor = -fgColor - 1 end
  if isPalette2 then bgColor = -bgColor - 1 end

  setBuff(buffChange, i, bgColor, fgColor, symbol)
end


-- Write changes to the screen
function update(force)
   -- Force update all bounds
  if force then
    drawX1, drawY1, drawX2, drawY2 = 1, 1, buffWidth, buffHeight
  end

  -- If there have been no changes then ignore
  if drawX1 > drawX2 or drawY1 > drawY2 then return end

  -- i = current index
  -- lineChange = index increment when changing to next y value
  -- fillw = Width of repeated length of background colors
  -- subgroup = the foreground subgroup of the background dict
  -- searchX = x value of end of repeated length
  -- searchIndex = index of end of repeated length
  -- currBg = temp var to store bg for current index since change buffer gets reset
  -- charCount = character counter for repeated string optimization
  -- j = temp loop variable
  -- colorChanges = dict of bg / fg color pixels grouped togther
  -- transparentChange = variable to track if any change vector is transparent
  -- noEmptySpaces = variable to track if there are not any empty spaces (no foreground chars)
  local i = getIndex(drawX1, drawY1)
  local lineChange = buffWidth - drawX2 + drawX1 - 1
  local fillw, subgroup, searchX, searchIndex, currBg, charcount, j
  local colorChanges = {}
  local aFgValue = nil
  local changeBg, changeFg, changeSym, buffBg, buffFg, buffSym
  local changeBg2, changeFg2, changeSym2

  for y = drawY1, drawY2 do
		x = drawX1
    while x <= drawX2 do
      changeBg, changeFg, changeSym = getBuff(buffChange, i)
      buffBg, buffFg, buffSym = getBuff(buffCurrent, i)

      if changeBg == nil or changeBg == -17 or changeFg == -17 then
      -- Ignore transparent characters
      -- If char is same as buffer below don't update it
      -- unless the force parameter is true.
      elseif force or not areEqual(buffSym, changeSym, buffBg, changeBg, buffFg, changeFg) then
        searchX = x + 1
        searchIndex = i + 1

        setBuff(buffCurrent, i, changeBg, changeFg, changeSym)

        -- Spaces don't need a foreground, assign filler value (black foreground)
        -- First space below is unicode char 0x2800 (not a regular space)
        if buffSym == "⠀"  or buffSym == " " then
          -- All "space" chars don't render a foreground color, so
          -- we set them all equal to 1 foreground to minimize redundant
          -- setForeground() calls
          if aFgValue == nil then aFgValue = buffFg
          else buffFg = aFgValue end
        end 

        -- Search for repeating chunks of characters of the same
        -- background
        while searchX <= drawX2 do
          changeBg2, changeFg2, changeSym2 = getBuff(buffChange, searchIndex)

          if not areEqual(1, 1, changeBg, changeBg2, 1, 1) then break end

          -- Update current "image" buffer
          setBuff(buffCurrent, searchIndex, changeB2, changeFg2, changeSym2)
          searchX = searchX + 1
          searchIndex = searchIndex + 1
        end

        fillw = searchX - x

        -- Create a dictionary by the background, then a sub
        -- dictionary of the foreground colors containing the points
        -- needed to draw. That way we minimize the number of setBackground
        -- and setForeground calls
        if colorChanges[changeBg] == nil then colorChanges[changeBg] = {} end
        currBg = changeBg

        j = i
        while j <= i + fillw - 1 do
          changeBg2, changeFg2, changeSym2 = getBuff(buffChange, j)

          if colorChanges[currBg][changeFg2] == nil then
            colorChanges[currBg][changeFg2] = {}
          end

          subgroup = colorChanges[currBg][changeFg2]
          
          -- Check for repeated strings
          charcount = 1
          for k = j + 1, i + fillw - 1 do
            if not areEqualIndex(k, j) then
              break
            end
            charcount = charcount + 1

            -- Change buffer reset
            setBuff(buffChange, k, -17, -17, " ")
          end
          
          subgroup[#subgroup + 1] = {x + j - i, y, changeSym2, charcount}

          -- Reset the change buffer
          setBuff(buffChange, j, -17, -17, " ")

          j = j + charcount
        end

        -- Increment x and i up to searchX - 1
        -- (Since there is a +1 below)
        x = searchX - 1
        i = i + fillw - 1
      end

      ::renderoptimizationend::

      -- This is required to avoid infinite loops
      -- when buffers are the same
      x = x + 1
      i = i + 1
    end

    i = i + lineChange
  end

  -- Draw color groups
  local t -- Temp variable
  local setCounter = 0
  local fillCounter = 1

  for bgcolor, group1 in pairs(colorChanges) do
    GPUsetBackground(absColor(bgcolor), bgcolor < 0)
    for fgcolor, group2 in pairs(group1) do
      GPUsetForeground(absColor(fgcolor), fgcolor < 0)

      for i = 1, #group2 do
        t = group2[i]

        if t[3] == "⠀" or t[3] == " " then -- First is braille 0x2800
          -- If spaces then use fill as it is less energy intensive
          if t[4] > 1 then
            GPUfill(t[1], t[2], t[4], 1, " ")
            fillCounter = fillCounter + 1
            goto continue
          end
        end

        -- Use fill or set depending on setToFillRatio to try to max out
        -- free gpu calls before they are queued to next tick
        if setCounter <= fillCounter * setToFillRatio then
          GPUset(t[1], t[2], rep(t[3], t[4]))
          setCounter = setCounter + 1
        else 
          GPUfill(t[1], t[2], t[4], 1, t[3]) 
          fillCounter = fillCounter + 1
        end

        ::continue::
      end
    end
  end

  -- Reset the drawX drawY bounds to largest / smallest possible
  drawX1, drawX2 = buffWidth, 0
  drawY1, drawY2 = buffHeight, 0 
end


-- Additional functions for the screen

-- Override GPU Functions
-- All files will now utilize the buffered drawing code
-- instead of native gpu codem which should be abstracted
function setBackground(color, isPalette)
  local prev = currentBg
  if isPalette then currentBg = -color - 1 else currentBg = color end
  if prev < 0 then
    return GPUgetPaletteColor(-prev - 1), -prev - 1
  end
  return prev
end

function setForeground(color, isPalette)
  local prev = currentFg
  if isPalette then currentFg = -color - 1 else currentFg = color end
  if prev < 0 then
    return GPUgetPaletteColor(-prev - 1), -prev - 1
  end
  return prev
end

function getBackground()
  return absColor(currentBg), currentBg < 0
end

function getForeground()
  return absColor(currentFg), currentFg < 0
end

function set(x, y, string, vertical, dontUpdate)
  local c1, c2 = absColor(currentFg), absColor(currentBg)
  if vertical then
    for y1 = 0, len(string) - 1 do
      setChar(x, y + y1, c1, c2, sub(string, y1 + 1, y1 + 1), currentFg < 0, currentBg < 0)
    end
  else
    for x1 = 0, len(string) - 1 do
      setChar(x + x1, y, c1, c2, sub(string, x1 + 1, x1 + 1), currentFg < 0, currentBg < 0)
    end
  end
  if not dontUpdate then update() end
end

-- Copy a region by a displacement tx and ty
-- Note that this directly updates to screen, as it is more
-- efficent to directly do the copy call
function copy(x, y, w, h, tx, ty)
  x, y, w, h = floor(x), floor(y), floor(w), floor(h)
  if x < 1 or y < 1 or x > buffWidth or y > buffHeight then return false end
  if w < 1 or h < 1 or w > buffWidth or h > buffHeight then return false end

  -- Literally just call copy() since it's 1 GPU call
  -- and the buffer's already properly updated
  update() -- Update current change buffer
  GPUcopy(x, y, w, h, tx, ty) 

  -- Update background BG buffer to match reality
  local boundX1, boundX2, xinc, boundY1, boundY2, yinc
  local bg, fg, sym

  boundX1, boundX2, xinc = x, x + w - 1, 1
  boundY1, boundY2, yinc = y, y + h - 1, 1
  if tx > 0 then
    boundX1, boundX2, xinc = boundX2, boundX1, -1
  end
  if ty > 0 then
    boundY1, boundY2, yinc = boundY2, boundY1, -1
  end
   
  for y1 = boundY1, boundY2, yinc do
    for x1 = boundX1, boundX2, xinc do
      if y1 > buffHeight or y1 + ty > buffHeight then goto loopend end
      if x1 < 1 or x1 > buffWidth or y1 < 1 then goto continue end
      if x1 + tx < 1 or x1 + tx > buffWidth or y1 + ty < 1 then goto continue end

      bg, fg, sym = getRaw(x1, y1)
      setBuff(buffCurrent, getIndex(x1 + tx, y1 + ty), bg, fg, sym)

      ::continue::
    end
  end
  ::loopend::
end 

function fill(x, y, w, h, symbol, dontUpdate)
  x, y, w, h = floor(x), floor(y), floor(w), floor(h)
  
  if len(symbol) ~= 1 then return false end
  if x < 1 or y < 1 or x > buffWidth or y > buffHeight then return false end
  if w < 1 or h < 1 or w > buffWidth or h > buffHeight then return false end

  -- Directly fill if area is large enough
  local useGpuFill = fillIfAreaIsGreaterThan <= w * h
  local i

  for x1 = x, x + w - 1 do
    for y1 = y, y + h - 1 do
      if useGpuFill then
        i = getIndex(x1, y1)

        setBuff(buffCurrent, i, currentBg, currentFg, symbol)
        setBuff(buffChange, i, -17, -17, " ")
      else 
        set(x1, y1, symbol, false, true)
      end
    end
  end
  
  if useGpuFill and not dontUpdate then
    GPUsetBackground(currentBg)
    GPUsetForeground(currentFg)
    GPUfill(x, y, w, h, symbol)
  elseif not dontUpdate then update() 
  else -- Do nothing
  end

  return true
end

function setResolution(w, h)
  local success = setResolution(w, h)
  if sucess then
    flush()
    GPUsetBackground(0)
    GPUfill(0, 0, w, h, " ")
  end
  return success
end

function getResolution()
  return buffWidth, buffHeight
end

function getWidth()
  return buffWidth
end

function getHeight()
  return buffHeight
end

-- Raw get for buffer values
function getRaw(x, y, dontNormalize)
  local index = getIndex(x, y)
  local t1, t2, t3 = getBuff(buffChange, index)  -- bg, fg, symbol

  if t1 ~= nil and t1 ~= -17 and t2 ~= -17 then
    if dontNormalize then return t1, t2, t3 end
    return normalizeColor(t1), normalizeColor(t2), t3
  end

  t1, t2, t3 = getBuff(buffCurrent, index)  -- bg, fg, symbol

  if dontNormalize then return t1, t2, t3 end
  return normalizeColor(t1), normalizeColor(t2), t3
end

-- Raw method to set current background
-- to adapt to the background of x, y and
-- current foreground to blend
-- Optionally, blendBg can be set to false to
-- not use adapative background
function setAdaptive(x, y, cfg, cbg, transparency, blendBg, blendBgTransparency)
  if transparency == 1 and blendBgTransparency then
    if cbg then setBackground(cbg) end
    if cfg then setForeground(cfg) end
    return
  end

  bg, fg, sym = getRaw(x, y)

  if blendBg then
    if blendBgTransparency then setBackground(color.blend(bg, cbg, transparency))
    else setBackground(color.getProminentColor(fg, bg, sym)) end
  end
  setForeground(color.blend(fg, cfg, transparency))
end


-- Screen drawing methods --

-- Draw a rectangle (border) with current bg and fg colors,
-- with optional transparency
function drawRect(x, y, w, h, transparency)
  x, y, w, h = floor(x), floor(y), floor(w), floor(h)
  if x < 1 or y < 1 or x > buffWidth or y > buffHeight then return false end
  if transparency == nil then transparency = 1 end

  local currentFgSave, currentBgSave = currentFg, currentBg
  local cfg, cbg = normalizeColor(currentFg), normalizeColor(currentBg)

  -- Corners
  setAdaptive(x, y, cfg, cbg, transparency, true, false)
  set(x, y, "┌")
  setAdaptive(x + w - 1, y, cfg, cbg, transparency, true, false)
  set(x + w - 1, y, "┐")
  setAdaptive(x, y + h - 1, cfg, cbg, transparency, true, false)
  set(x, y + h - 1, "└")
  setAdaptive(x + w, y + h - 1, cfg, cbg, transparency, true, false)
  set(x + w - 1, y + h - 1, "┘")

  -- Top and bottom
  for x1 = x + 1, x + w - 2 do
    setAdaptive(x1, y, cfg, cbg, transparency, true, false)
    set(x1, y, "─")
    setAdaptive(x1, y + h - 1, cfg, cbg, transparency, true, false)
    set(x1, y + h - 1, "─")
  end

  -- Sides
  for y1 = y + 1, y + h - 2 do
    setAdaptive(x, y1, cfg, cbg, transparency, true, false)
    set(x, y1, "│")
    setAdaptive(x + w - 1, y1, cfg, cbg, transparency, true, false)
    set(x + w - 1, y1, "│")
  end

  -- Reset original bg / fg colors
  currentBg = currentBgSave
  currentFg = currentFgSave
  return true
end

-- Fill a rectangle with the current bg and fg colors,
-- with optional transparency. Because of transparency
-- we have to reimplement fill code
function fillRect(x, y, w, h, transparency)
  x, y, w, h = floor(x), floor(y), floor(w), floor(h)
  if x < 1 or y < 1 or x > buffWidth or y > buffHeight then return false end
  if transparency == nil then transparency = 1 end

  local currentFgSave, currentBgSave = currentFg, currentBg
  local cfg, cbg = normalizeColor(currentFg), normalizeColor(currentBg)

  -- Directly fill if area is large enough
  for x1 = x, x + w - 1 do
  for y1 = y, y + h - 1 do
    if x1 > buffWidth then goto continue end
    if y1 > buffHeight then break end
    setAdaptive(x1, y1, cfg, cbg, transparency, true, true)
    set(x1, y1, " ", false, true)

    ::continue::
  end end

  -- Reset original bg / fg colors
  currentBg = currentBgSave
  currentFg = currentFgSave
  return true
end

-- Draw a string at the location (Straight line, newlines ignore)
-- If transparency is enabled, foreground is blended w/ bg
-- If blendBg is enabled, the background will be selected to try
-- to camouflage itself with the existing buffer
function drawText(x, y, string, transparency, blendBg)
  x, y = floor(x), floor(y)

  -- Save current colors
  local currentFgSave, currentBgSave = currentFg, currentBg
  local cfg, cbg = normalizeColor(currentFg), normalizeColor(currentBg)
  if transparency == nil then transparency = 1 end

  for dx = 0, len(string) - 1 do
    if x < 1 then goto continue end
    if x > buffWidth then break end

    setAdaptive(x + dx, y, cfg, false, transparency, blendBg, false)
    set(x + dx, y, sub(string, dx + 1, dx + 1))

    ::continue::
  end

  -- Reset original bg / fg colors
  currentBg = currentBgSave
  currentFg = currentFgSave
  return true
end

function drawEllipse()
end

function fillEllipse()
end

-- Draw a line (Using braille characters)
-- from 1 point to another, optionally with transparency
-- Optional line character, which will override ALL line characters
function drawLine(x1, y1, x2, y2, transparency, lineChar)
  x1, y1, x2, y2 = floor(x1), floor(y1), floor(x2), floor(y2)
  if transparency == nil then transparency = 1 end

  -- Save current colors
  local currentFgSave, currentBgSave = currentFg, currentBg
  local cfg, cbg = normalizeColor(currentFg), normalizeColor(currentBg)
  local lineChar

  -- Horz line
  if y1 == y2 then
    lineChar = lineChar or "▔"
    for x = x1, x2 do
      if x < 1 then goto continue end
      if x > buffWidth then break end

      setAdaptive(x, y1, cfg, false, transparency, true, false)
      set(x, y1, lineChar, false, true)

      ::continue::
    end
    return true
  end

  -- Vertical line
  if x1 == x2 then
    lineChar = lineChar or "▏"
    for y = y1, y2 do
      if y < 1 then goto continue end
      if y > buffHeight then break end

      setAdaptive(x1, y, cfg, false, transparency, true, false)
      set(x1, y, lineChar, false, true)

      ::continue::
    end
    return true
  end

  -- TODO LINE

  -- Reset original bg / fg colors
  currentBg = currentBgSave
  currentFg = currentFgSave
  return true
end

-- Set gpu proxy
setGPUProxy(gpu)

return {
  setGPUProxy = setGPUProxy,
  getGPUProxy = getGPUProxy,
  bind = bind,
  flush = flush,
  clear = clear,
  setChar = setChar,
  update = update,
  setBackground = setBackground,
  setForeground = setForeground,
  getBackground = getBackground,
  getForeground = getForeground,
  set = set,
  copy = copy,
  fill = fill,
  setResolution = setResolution,
  getResolution = getResolution,
  getWidth = getWidth,
  getHeight = getHeight,
  drawRect = drawRect,
  fillRect = fillRect,
  drawText = drawText,
  drawEllipse = drawEllipse,
  fillEllipse = fillEllipse,
  drawLine = drawLine
}
