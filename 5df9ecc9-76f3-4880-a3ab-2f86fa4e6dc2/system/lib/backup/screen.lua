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

-- Limits for drawing on the buffer, to avoid 
-- checking for excessive changes
local drawX1, drawY1, drawX2, drawY2 = 0, 0, buffWidth, buffHeight

-- Current fg / bg colors for set and fill
local currentBg, currentFg = 0, 0xFFFFFF

-- Optimization for lua / gpu proxying
local gpuProxy, fill, set, setBackground, setForeground
local getResolution, setResolution, getPaletteColor, copy, setResolution
local getBackground, getForeground

local rep = string.rep
local sub = unicode.sub
local floor = math.floor

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

-- Palette index = (-index - 1), this takes the "absolute"
-- value to convert to the proper index if negative
local function absColor(val) 
  if val < 0 then return -val - 1 end
  return val
end 

-- Normalize a color to a 24 bit int (Including)
-- palette indexes
local function normalizeColor(val)
  if val < 0 then return getPaletteColor(-val - 1) end
  return val
end

--------------------------------------------------------
local api = {}

-- Set GPU Proxy for the screen --
function api.setGPUProxy(gpu)
  -- Define local variables
  gpuProxy = gpu
  fill, set, copy = gpu.fill, gpu.set, gpu.copy
  setBackground, setForeground = gpu.setBackground, gpu.setForeground
  getBackground, getForeground = gpu.getBackground, gpu.getForeground
  getResolution, setResolution = gpu.getResolution, gpu.setResolution
  getPaletteColor = gpu.getPaletteColor

  -- Override GPU API
  gpu.set, gpu.copy, gpu.fill = api.set, api.copy, api.fill
  gpu.setBackground, gpu.setForeground = api.setBackground, api.setForeground
  gpu.getBackground, gpu.getForeground = api.getBackground, api.getForeground
  gpu.setResolution, gpu.getResolution = api.setResolution, api.getResolution

  -- Prefill buffer
  api.flush()
end

-- Get GPU Proxy for the screen --
function api.getGPUProxy()
  return gpuProxy
end

-- Bind the gpu proxy to a screen address --
function api.bind(screenAddress, reset)
  local success, reason = gpuProxy.bind(address, reset)
	if success then
		if reset then api.setResolution(gpuProxy.maxResolution())
    else api.setResolution(bufferWidth, bufferHeight) end
  end
  return success, reason
end

-- Flush the buffer and re-create each array --
function api.flush(w, h)
  if w == nil or h == nil then
    w, h = getResolution()
  end
  buffWidth = w
  buffHeight = h

  drawX1, drawX2 = w, 0
  drawY1, drawY2 = h, 0

  -- currentBg = 0
  -- currentFg = 0xFFFFFF

  buffBg, buffFg, buffSym = {}, {}, {}
  changeBg, changeFg, changeSym = {}, {}, {}

  -- Prefill the buffers to avoid rehashing (-17 is transparent) --
  for i = 1, w * h do
    buffBg[i], buffFg[i], buffSym[i] = 0, 0, " "
    changeBg[i], changeFg[i], changeSym[i] = -17, -17, " "
  end
end

-- Clear the screen by filling with black whitespace chars --
function api.clear(color)
  api.setBackground(color)
  api.fill(0, 0, buffWidth, buffHeight, " ")

  drawX1, drawX2 = w, 0
  drawY1, drawY2 = h, 0
end

-- Set a specific character (internal method) --
function api.setChar(x, y, fgColor, bgColor, symbol, isPalette1, isPalette2)
  if x < 1 or y < 1 or x > buffWidth or y > buffHeight then return false end
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

  changeBg[i], changeFg[i], changeSym[i] = bgColor, fgColor, symbol
end


-- Write changes to the screen
function api.update(force)
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

  for y = drawY1, drawY2 do
		x = drawX1
    while x <= drawX2 do
      if changeBg[i] == -17 or changeFg[i] == -17 then
      -- Ignore transparent characters
      -- If char is same as buffer below don't update it
      -- unless the force parameter is true.
      elseif force or not areEqual(buffSym[i], changeSym[i], buffBg[i], changeBg[i], buffFg[i], changeFg[i]) then
        searchX = x + 1
        searchIndex = i + 1
        
        buffSym[i], buffBg[i], buffFg[i] = changeSym[i], changeBg[i], changeFg[i]

        -- Spaces don't need a foreground, assign filler value (black foreground)
        -- First space below is unicode char 0x2800 (not a regular space)
        if buffSym[i] == "⠀"  or buffSym[i] == " " then
          -- All "space" chars don't render a foreground color, so
          -- we set them all equal to 1 foreground to minimize redundant
          -- setForeground() calls
          if aFgValue ~= nil then aFgValue = buffFg[i] end
          buffFg[i] = aFgValue
        end 

        -- Search for repeating chunks of characters of the same
        -- background
        while searchX <= drawX2 do
          if not areEqual(1, 1, changeBg[i], changeBg[searchIndex], 1, 1) then break end

          -- Update current "image" buffer
          buffSym[searchIndex], buffBg[searchIndex], buffFg[searchIndex] = 
            changeSym[searchIndex], changeBg[searchIndex], changeFg[searchIndex]
          searchX = searchX + 1
          searchIndex = searchIndex + 1
        end

        fillw = searchX - x

        -- Create a dictionary by the background, then a sub
        -- dictionary of the foreground colors containing the points
        -- needed to draw. That way we minimize the number of setBackground
        -- and setForeground calls
        if colorChanges[changeBg[i]] == nil then colorChanges[changeBg[i]] = {} end
        currBg = changeBg[i]

        j = i
        while j <= i + fillw - 1 do
          if colorChanges[currBg][changeFg[j]] == nil then
            colorChanges[currBg][changeFg[j]] = {}
          end

          subgroup = colorChanges[currBg][changeFg[j]]
          
          -- Check for repeated strings
          charcount = 1
          for k = j + 1, i + fillw - 1 do
            if not areEqual(buffSym[j], changeSym[k], buffBg[j], changeBg[k], buffFg[j], changeFg[k]) then
              break
            end
            charcount = charcount + 1

            -- Change buffer reset
            -- changeBg[k], changeFg[k], changeSym[k] = -17, -17, " "
          end
          
          subgroup[#subgroup + 1] = {x + j - i, y, changeSym[j], charcount}

          -- Reset the change buffer
          changeBg[j], changeFg[j] = -17, -17
          changeSym[j] = " "

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
    setBackground(absColor(bgcolor), bgcolor < 0)
    for fgcolor, group2 in pairs(group1) do
      if fgcolor == -17 then
        -- There is 1 case where we can skip this, where there is only spaces so no foreground is needed
      else setForeground(absColor(fgcolor), fgcolor < 0) end 

      for i = 1, #group2 do
        t = group2[i]

        if t[3] == "⠀" or t[3] == " " then -- First is braille 0x2800
          -- If spaces then use fill as it is less energy intensive
          if t[4] > 1 then
            fill(t[1], t[2], t[4], 1, " ")
            fillCounter = fillCounter + 1
            goto continue
          end
        end

        -- Use fill or set depending on setToFillRatio to try to max out
        -- free gpu calls before they are queued to next tick
        if setCounter <= fillCounter * setToFillRatio then
          set(t[1], t[2], rep(t[3], t[4]))
          setCounter = setCounter + 1
        else 
          fill(t[1], t[2], t[4], 1, t[3]) 
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
function api.setBackground(color, isPalette)
  local prev = currentBg
  if isPalette then currentBg = -color - 1 else currentBg = color end
  if prev < 0 then
    return getPaletteColor(-prev - 1), -prev - 1
  end
  return prev
end

function api.setForeground(color, isPalette)
  local prev = currentFg
  if isPalette then currentFg = -color - 1 else currentFg = color end
  if prev < 0 then
    return getPaletteColor(-prev - 1), -prev - 1
  end
  return prev
end

function api.getBackground()
  return absColor(currentBg), currentBg < 0
end

function api.getForeground()
  return absColor(currentFg), currentFg < 0
end

function api.set(x, y, string, vertical, dontUpdate)
  local c1, c2 = absColor(currentFg), absColor(currentBg)
  if vertical then
    for y1 = 0, #string - 1 do
      api.setChar(x, y + y1, c1, c2, sub(string, y1 + 1, y1 + 1), currentFg < 0, currentBg < 0)
    end
  else
    for x1 = 0, #string - 1 do
      api.setChar(x + x1, y, c1, c2, sub(string, x1 + 1, x1 + 1), currentFg < 0, currentBg < 0)
    end
  end
  if not dontUpdate then api.update() end
end

-- Copy a region by a displacement tx and ty
-- Note that this directly updates to screen, as it is more
-- efficent to directly do the copy call
function api.copy(x, y, w, h, tx, ty)
  x, y, w, h = floor(x), floor(y), floor(w), floor(h)
  if x < 1 or y < 1 or x > buffWidth or y > buffHeight then return false end
  if w < 1 or h < 1 or w > buffWidth or h > buffHeight then return false end
  local i

  -- Literally just call copy() since it's 1 GPU call
  -- and the buffer's already properly updated
  api.update() -- Update current change buffer
  copy(x, y, w, h, tx, ty) 

  -- Update background BG buffer to match reality
  local boundX1, boundX2, xinc, boundY1, boundY2, yinc
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

      i = getIndex(x1, y1)
      buffBg[i], buffFg[i], buffSym[i] = api.getRaw(x1, y1)

      ::continue::
    end
  end
  ::loopend::
end 

function api.fill(x, y, w, h, symbol, dontUpdate)
  x, y, w, h = floor(x), floor(y), floor(w), floor(h)
  
  if #symbol ~= 1 then return false end
  if x < 1 or y < 1 or x > buffWidth or y > buffHeight then return false end
  if w < 1 or h < 1 or w > buffWidth or h > buffHeight then return false end

  -- Directly fill if area is large enough
  local useGpuFill = fillIfAreaIsGreaterThan <= w * h
  local i

  for x1 = x, x + w - 1 do
    for y1 = y, y + h - 1 do
      if useGpuFill then
        i = getIndex(x1, y1)
        buffBg[i], buffFg[i], buffSym[i] = currentBg, currentFg, symbol
        changeBg[i], changeFg[i], changeSym[i] = -17, -17, " "
      else 
        api.set(x1, y1, symbol, false, true)
      end
    end
  end
  
  if useGpuFill and not dontUpdate then
    setBackground(currentBg)
    setForeground(currentFg)
    fill(x, y, w, h, symbol)
  elseif not dontUpdate then api.update() 
  else -- Do nothing
  end

  return true
end

function api.setResolution(w, h)
  local success = setResolution(w, h)
  if sucess then
    api.flush()
    setBackground(0)
    fill(0, 0, w, h, " ")
  end
  return success
end

function api.getResolution()
  return buffWidth, buffHeight
end

function api.getWidth()
  return buffWidth
end

function api.getHeight()
  return buffHeight
end

-- Raw get for buffer values
function api.getRaw(x, y, dontNormalize)
  local index = getIndex(x, y)

  if changeBg[index] ~= -17 and changeFg[index] ~= -17 then
    if dontNormalize then return changeBg[index], changeFg[index], changeSym[index] end
    return normalizeColor(changeBg[index]), normalizeColor(changeFg[index]), changeSym[index]
  end

  if dontNormalize then return buffBg[index], buffFg[index], buffSym[index] end
  return normalizeColor(buffBg[index]), normalizeColor(buffFg[index]), buffSym[index]
end

-- Raw method to set current background
-- to adapt to the background of x, y and
-- current foreground to blend
-- Optionally, blendBg can be set to false to
-- not use adapative background
function api.setAdaptive(x, y, cfg, cbg, transparency, blendBg, blendBgTransparency)
  bg, fg, sym = api.getRaw(x, y)

  if blendBg then
    if blendBgTransparency then api.setBackground(color.blend(bg, cbg, transparency))
    else api.setBackground(color.getProminentColor(fg, bg, sym)) end
  end
  api.setForeground(color.blend(fg, cfg, transparency))
end


-- Screen drawing methods --

-- Draw a rectangle (border) with current bg and fg colors,
-- with optional transparency
function api.drawRect(x, y, w, h, symbol, transparency)
  if #symbol ~= 1 then return false end
  x, y, w, h = floor(x), floor(y), floor(w), floor(h)
  if x < 1 or y < 1 or x > buffWidth or y > buffHeight then return false end

  local currentFgSave, currentBgSave = currentFg, currentBg
  local cfg, cbg = normalizeColor(currentFg), normalizeColor(currentBg)

  -- Corners
  api.set(x, y, " ")

  -- Lines

  -- Reset original bg / fg colors
  currentBg = currentBgSave
  currentFg = currentFgSave
  return true
end

-- Fill a rectangle with the current bg and fg colors,
-- with optional transparency. Because of transparency
-- we have to reimplement fill code
function api.fillRect(x, y, w, h, symbol, transparency)
  if #symbol ~= 1 then return false end
  x, y, w, h = floor(x), floor(y), floor(w), floor(h)
  if x < 1 or y < 1 or x > buffWidth or y > buffHeight then return false end

  local currentFgSave, currentBgSave = currentFg, currentBg
  local cfg, cbg = normalizeColor(currentFg), normalizeColor(currentBg)

  -- Directly fill if area is large enough
  for x1 = x, x + w - 1 do
  for y1 = y, y + h - 1 do
    if x1 > buffWidth then goto continue end
    if y1 > buffHeight then break end
    api.setAdaptive(x1, y1, cfg, cbg, transparency, true, true)
    api.set(x1, y1, symbol, false, true)

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
function api.drawText(x, y, string, transparency, blendBg)
  x, y = floor(x), floor(y)

  -- Save current colors
  local currentFgSave, currentBgSave = currentFg, currentBg
  local cfg, cbg = normalizeColor(currentFg), normalizeColor(currentBg)

  for dx = 0, #string - 1 do
    if x < 1 then goto continue end
    if x > buffWidth then break end

    api.setAdaptive(x + dx, y, cfg, false, transparency, blendBg, false)
    api.set(x + dx, y, sub(string, dx + 1, dx + 1))

    ::continue::
  end

  -- Reset original bg / fg colors
  currentBg = currentBgSave
  currentFg = currentFgSave
  return true
end

function api.drawEllipse()
end

function api.fillEllipse()
end

-- Draw a line (Using braille characters)
-- from 1 point to another, optionally with transparency
-- Optional line character, which will override ALL line characters
function api.drawLine(x1, y1, x2, y2, transparency, lineChar)
  x1, y1, x2, y2 = floor(x1), floor(y1), floor(x2), floor(y2)

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

      api.setAdaptive(x, y1, cfg, false, transparency, true, false)
      api.set(x, y1, lineChar, false, true)

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

      api.setAdaptive(x1, y, cfg, false, transparency, true, false)
      api.set(x1, y, lineChar, false, true)

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
api.setGPUProxy(gpu)

return api
